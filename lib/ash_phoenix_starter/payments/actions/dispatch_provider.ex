defmodule AshPhoenixStarter.Payments.Actions.DispatchProvider do
  alias AshPhoenixStarter.Payments.{PropertyGateway, Registry, Transaction}

  def to_minor_units(%Money{} = money) do
    {_currency, amount_int, _exponent, _remainder} = Money.to_integer_exp(money)
    {amount_int, Atom.to_string(money.currency)}
  end

  def run_authorize(%Transaction{} = tx, provider_opts) do
    {amount_cents, currency} = to_minor_units(tx.amount)

    with {:ok, module} <- Registry.fetch(tx.provider_id),
         {:ok, gateway} <- fetch_gateway(tx.property_id, tx.provider_id) do
      opts =
        provider_opts
        |> Map.to_list()
        |> Enum.map(fn {k, v} -> {if(is_atom(k), do: k, else: String.to_existing_atom(k)), v} end)
        |> Keyword.merge(config: gateway.credentials, idempotency_key: tx.idempotency_key)

      case module.authorize(amount_cents, currency, opts) do
        {:ok, resp} ->
          next_state = if resp.status == :captured, do: :captured, else: :authorized

          tx
          |> Ash.Changeset.for_update(:authorize, %{
            next_state: next_state,
            provider_transaction_id: resp.transaction_id,
            redirect_url: Map.get(resp, :redirect_url),
            raw_response: resp.raw_response
          })
          |> Ash.update(authorize?: false)

        {:error, reason} ->
          tx
          |> Ash.Changeset.for_update(:authorize, %{
            next_state: :failed,
            error_reason: inspect(reason)
          })
          |> Ash.update(authorize?: false)
      end
    end
  end

  def run_capture(changeset, _ctx) do
    tx = changeset.data
    capture_money = Ash.Changeset.get_argument(changeset, :capture_amount) || tx.amount
    {amount_cents, currency} = to_minor_units(capture_money)

    with {:ok, module} <- Registry.fetch(tx.provider_id),
         {:ok, gateway} <- fetch_gateway(tx.property_id, tx.provider_id),
         {:ok, resp} <-
           module.capture(tx.provider_transaction_id,
             config: gateway.credentials,
             amount_cents: amount_cents,
             currency: currency,
             idempotency_key: "#{tx.idempotency_key}_cap"
           ) do
      changeset
      |> Ash.Changeset.force_change_attribute(:raw_response, resp.raw_response)
      |> AshStateMachine.transition_state(:captured)
    else
      {:error, reason} ->
        Ash.Changeset.add_error(changeset, field: :state, message: inspect(reason))
    end
  end

  def run_void(changeset, _ctx) do
    tx = changeset.data
    {amount_cents, currency} = to_minor_units(tx.amount)

    with {:ok, module} <- Registry.fetch(tx.provider_id),
         {:ok, gateway} <- fetch_gateway(tx.property_id, tx.provider_id),
         {:ok, resp} <-
           module.void(tx.provider_transaction_id,
             config: gateway.credentials,
             amount_cents: amount_cents,
             currency: currency,
             idempotency_key: "#{tx.idempotency_key}_void"
           ) do
      changeset
      |> Ash.Changeset.force_change_attribute(:raw_response, resp.raw_response)
      |> AshStateMachine.transition_state(:voided)
    else
      {:error, reason} ->
        Ash.Changeset.add_error(changeset, field: :state, message: inspect(reason))
    end
  end

  def run_refund(changeset, _ctx) do
    tx = changeset.data
    refund_money = Ash.Changeset.get_argument(changeset, :refund_amount)
    reason = Ash.Changeset.get_argument(changeset, :reason)
    {amount_cents, currency} = to_minor_units(refund_money)

    with true <-
           Money.equal?(tx.amount, refund_money) or
             match?({:ok, true}, Money.lt?(refund_money, tx.amount)),
         {:ok, module} <- Registry.fetch(tx.provider_id),
         {:ok, gateway} <- fetch_gateway(tx.property_id, tx.provider_id),
         {:ok, resp} <-
           module.refund(tx.provider_transaction_id, amount_cents,
             config: gateway.credentials,
             currency: currency,
             reason: reason,
             idempotency_key: "#{tx.idempotency_key}_ref_#{amount_cents}"
           ) do
      next_state =
        if Money.equal?(tx.amount, refund_money), do: :refunded, else: :partially_refunded

      changeset
      |> Ash.Changeset.force_change_attribute(:refunded_amount, refund_money)
      |> Ash.Changeset.force_change_attribute(:raw_response, resp.raw_response)
      |> AshStateMachine.transition_state(next_state)
    else
      _ ->
        Ash.Changeset.add_error(changeset,
          field: :refunded_amount,
          message: "Invalid refund amount"
        )
    end
  end

  defp fetch_gateway(property_id, provider_id) do
    PropertyGateway
    |> Ash.Query.filter(
      property_id == ^property_id and provider_id == ^provider_id and active == true
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :gateway_not_configured}
      {:ok, gateway} -> {:ok, gateway}
      err -> err
    end
  end
end
