defmodule AshPhoenixStarterWeb.StripeWebhookController do
  use AshPhoenixStarterWeb, :controller

  require Logger

  alias AshPhoenixStarter.Workers.DropletProvisionerWorker

  @doc """
  Handles incoming webhook events from Stripe.
  Verifies the signature using the raw request body and dispatches actions.
  """
  def create(conn, _params) do
    with {:ok, payload} <- read_raw_body(conn),
         {:ok, signature} <- get_stripe_signature(conn),
         {:ok, event} <- verify_signature(payload, signature) do
      handle_stripe_event(event)

      send_resp(conn, :ok, "Webhook handled successfully")
    else
      {:error, reason} ->
        Logger.error("Stripe webhook processing failed: #{inspect(reason)}")
        conn |> send_resp(:bad_request, "Webhook Error: #{inspect(reason)}")
    end
  end

  # --- Event Dispatcher ---

  defp handle_stripe_event(%{
         "type" => "checkout.session.completed",
         "data" => %{"object" => session}
       }) do
    customer_email = session["customer_email"] || get_in(session, ["customer_details", "email"])

    # Placeholder: Replace with your actual DigitalOcean snapshot ID or metadata lookup
    snapshot_id = System.get_env("DEFAULT_DO_SNAPSHOT_ID") || "your_snapshot_id_here"

    if customer_email do
      Logger.info(
        "Checkout completed for #{customer_email}. Triggering automated droplet provisioner..."
      )

      # Fire and forget safely in a background worker task
      DropletProvisionerWorker.run_async(customer_email, snapshot_id)
    else
      Logger.error("Checkout session completed, but customer email was missing from payload.")
    end
  end

  defp handle_stripe_event(%{"type" => other_type}) do
    Logger.info("Unhandled Stripe webhook event type received: #{other_type}")
    :ok
  end

  # --- Security & Verification Helpers ---

  defp read_raw_body(conn) do
    case Plug.Conn.read_body(conn, length: 1_000_000) do
      {:ok, body, _conn} -> {:ok, body}
      {:more, _, _} -> {:error, :body_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_stripe_signature(conn) do
    case get_req_header(conn, "stripe-signature") do
      [signature | _] -> {:ok, signature}
      [] -> {:error, :missing_stripe_signature_header}
    end
  end

  defp verify_signature(payload, signature) do
    signing_secret = System.fetch_env!("STRIPE_WEBHOOK_SECRET")

    # If you are using the `stripity_stripe` package, you can use its built-in validator:
    case Stripe.Webhook.construct_event(payload, signature, signing_secret, response_as: :map) do
      {:ok, event} -> {:ok, event}
      {:error, error} -> {:error, error}
    end
  end
end
