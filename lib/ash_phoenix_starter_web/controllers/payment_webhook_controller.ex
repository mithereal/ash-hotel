defmodule HotelWeb.PaymentWebhookController do
  use HotelWeb, :controller
  require Ash.Query

  alias Hotel.Payments.{Lock, PropertyGateway, Registry, Transaction}

  def receive(conn, %{"provider_id" => provider_id, "property_id" => property_id}) do
    raw_body = conn.assigns[:raw_body] || ""
    headers = Map.new(conn.req_headers)
    system_actor = %{role: :system, property_id: property_id}

    with {:ok, handler} <- Registry.fetch(provider_id),
         {:ok, gateway} <- fetch_gateway(property_id, provider_id, system_actor),
         {:ok, event} <- Registry.invoke_webhook(handler, raw_body, headers, gateway.credentials),
         {:ok, next_state} <- map_event_to_state(event.event),
         {:ok, tx} <- find_transaction(property_id, event.transaction_id, system_actor),
         {:ok, _updated_tx} <- apply_locked_transition(tx, next_state, event.raw, system_actor) do
      Phoenix.PubSub.broadcast(Hotel.PubSub, "payments:#{property_id}", {:payment_event, event})
      send_resp(conn, 200, "ok")
    else
      {:ok, :ignore} ->
        send_resp(conn, 200, "ignored")

      {:error, :gateway_not_found} ->
        send_resp(conn, 404, "gateway not configured")

      {:error, :provider_not_found} ->
        send_resp(conn, 404, "unknown provider")

      {:error, :transaction_not_found} ->
        # Return 202 so gateways don't endlessly retry webhooks for external/untracked charges
        send_resp(conn, 202, "accepted_unmatched")

      {:error, :payment_in_progress} ->
        # Return 409/503 so the gateway retries shortly after the active checkout lock releases
        send_resp(conn, 503, "busy_retry")

      {:error, _reason} ->
        send_resp(conn, 400, "invalid webhook")
    end
  end

  defp apply_locked_transition(tx, next_state, raw_payload, actor) do
    Lock.with_reservation_lock(tx.reservation_id, fn ->
      # Re-fetch inside the lock to ensure we have the latest AshStateMachine state
      with {:ok, fresh_tx} <- Ash.get(Transaction, tx.id, actor: actor) do
        if fresh_tx.state == next_state do
          {:ok, fresh_tx}
        else
          fresh_tx
          |> Ash.Changeset.for_update(
            :webhook_transition,
            %{next_state: next_state, raw_response: raw_payload},
            actor: actor
          )
          |> Ash.update()
        end
      end
    end)
  end

  defp fetch_gateway(property_id, provider_id, actor) do
    PropertyGateway
    |> Ash.Query.filter(
      property_id == ^property_id and provider_id == ^provider_id and active == true
    )
    |> Ash.read_one(actor: actor)
    |> case do
      {:ok, nil} -> {:error, :gateway_not_found}
      {:ok, gateway} -> {:ok, gateway}
      err -> err
    end
  end

  defp find_transaction(property_id, provider_tx_id, actor) do
    Transaction
    |> Ash.Query.filter(
      property_id == ^property_id and provider_transaction_id == ^provider_tx_id
    )
    |> Ash.read_one(actor: actor)
    |> case do
      {:ok, nil} -> {:error, :transaction_not_found}
      {:ok, tx} -> {:ok, tx}
      err -> err
    end
  end

  defp map_event_to_state(:payment_authorized), do: {:ok, :authorized}
  defp map_event_to_state(:payment_captured), do: {:ok, :captured}
  defp map_event_to_state(:payment_voided), do: {:ok, :voided}
  defp map_event_to_state(:payment_refunded), do: {:ok, :refunded}
  defp map_event_to_state(:payment_failed), do: {:ok, :failed}
  defp map_event_to_state(_), do: {:ok, :ignore}
end
