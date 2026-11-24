defmodule AshPhoenixStarterWeb.LicenseWebhookController do
  use AshPhoenixStarterWeb, :controller

  alias AshPhoenixStarter.Billing.{TenantUsage, UsageTracker}

  def update_license(
        conn,
        %{
          "organization_id" => org_id,
          "region_id" => region_id,
          "storage_limit_bytes" => storage_limit,
          "bandwidth_limit_bytes" => bandwidth_limit
        } = params
      ) do
    with :ok <- verify_worker_secret(conn),
         :ok <- persist_new_limits(org_id, region_id, storage_limit, bandwidth_limit) do
      # 1. Flush & restart UsageTracker on its regional OCI node so new limits take effect immediately
      UsageTracker.reload_limits(region_id, org_id)

      # 2. Clear any quota warnings and flash a confirmation in the hotel's open LiveView
      Phoenix.PubSub.broadcast(
        AshPhoenixStarter.PubSub,
        "notifications:org:#{org_id}",
        {:plan_updated, params["tier"] || "active"}
      )

      json(conn, %{ok: true, organization_id: org_id, region_id: region_id})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid worker authorization token"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  defp verify_worker_secret(conn) do
    expected = System.get_env("INTERNAL_WORKER_SECRET")

    with ["Bearer " <> provided] <- get_req_header(conn, "authorization"),
         true <- is_binary(expected) and expected != "",
         true <- Plug.Crypto.secure_compare(provided, expected) do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp persist_new_limits(org_id, region_id, storage_limit, bandwidth_limit) do
    period_start = Date.beginning_of_month(Date.utc_today())

    TenantUsage
    |> Ash.Changeset.for_create(
      :set_limits,
      %{
        organization_id: org_id,
        region_id: to_string(region_id),
        period_start: period_start,
        storage_limit_bytes: storage_limit,
        bandwidth_limit_bytes: bandwidth_limit
      },
      authorize?: false
    )
    |> Ash.create()
    |> case do
      {:ok, _usage} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
