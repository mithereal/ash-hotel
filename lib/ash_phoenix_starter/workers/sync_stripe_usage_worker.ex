defmodule AshPhoenixStarter.Billing.Workers.SyncStripeUsageWorker do
  @moduledoc """
  Daily Oban cron worker that calculates bandwidth + storage overages per hotel
  for the current billing month and reports incremental GBs to Stripe Billing Meters.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Ash.Query
  require Logger
  alias AshPhoenixStarter.Billing.TenantUsage

  @bytes_per_gb 1_073_741_824

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    period_start = Date.beginning_of_month(Date.utc_today())

    TenantUsage
    |> Ash.Query.filter(period_start == ^period_start)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&sync_tenant_overage/1)

    :ok
  end

  defp sync_tenant_overage(%TenantUsage{} = usage) do
    bw_overage = max(0, usage.bandwidth_bytes - usage.bandwidth_limit_bytes)
    storage_overage = max(0, usage.storage_bytes - usage.storage_limit_bytes)

    total_overage_gb = div(bw_overage + storage_overage, @bytes_per_gb)
    unbilled_gb = total_overage_gb - usage.reported_overage_gb

    if unbilled_gb > 0 do
      with {:ok, stripe_customer_id} <- fetch_stripe_customer_id(usage.organization_id),
           :ok <- send_stripe_meter_event(usage, stripe_customer_id, unbilled_gb) do
        usage
        |> Ash.Changeset.for_update(:update, %{reported_overage_gb: total_overage_gb},
          authorize?: false
        )
        |> Ash.update!()
      end
    end
  end

  defp send_stripe_meter_event(usage, stripe_customer_id, unbilled_gb) do
    api_key = System.get_env("STRIPE_SECRET_KEY")
    # Deterministic idempotency key ensures Oban retries never double-bill
    idempotency_key = "overage_#{usage.id}_#{usage.reported_overage_gb + unbilled_gb}"

    body =
      URI.encode_query(%{
        "event_name" => "hotel_platform_overage_gb",
        "payload[stripe_customer_id]" => stripe_customer_id,
        "payload[value]" => to_string(unbilled_gb),
        "identifier" => idempotency_key
      })

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    case Req.post("https://stripe.com", body: body, headers: headers) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: resp}} ->
        Logger.error(
          "Stripe meter sync failed (#{status}) for org=#{usage.organization_id}: #{inspect(resp)}"
        )

        {:error, :stripe_api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  alias AshPhoenixStarter.Accounts.Organization

  defp fetch_stripe_customer_id(organization_id) do
    case Ash.get(Organization, organization_id, authorize?: false) do
      {:ok, %{stripe_customer_id: customer_id}}
      when is_binary(customer_id) and customer_id != "" ->
        {:ok, customer_id}

      {:ok, _org} ->
        {:error, :missing_stripe_customer}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
