defmodule AshPhoenixStarter.Licensing.CloudflareSync do
  @moduledoc """
  Pulls the latest signed Ed25519 license key directly from the Cloudflare Worker
  license server and verifies it locally. Allows self-hosted instances to refresh
  their tier immediately even if the Render control plane is offline.
  """

  alias AshPhoenixStarter.Billing.Tiers
  alias AshPhoenixStarter.Licensing.Verifier
  alias AshPhoenixStarter.Settings.Manager

  @doc """
  Fetches the latest license key from Cloudflare for the current tenant/license,
  verifies its Ed25519 signature locally, and updates local settings.
  """
  @spec refresh() :: {:ok, atom()} | {:error, term()}
  def refresh do
    worker_url = Application.get_env(:AshPhoenixStarter, :cloudflare_license_url)

    current_key =
      Manager.get(:license_key) ||
        Application.get_env(:AshPhoenixStarter, :license_key)

    tenant_id =
      Application.get_env(:AshPhoenixStarter, :tenant_id) ||
        extract_tenant_id(current_key)

    cond do
      not is_binary(worker_url) or worker_url == "" ->
        {:error, :missing_cloudflare_url}

      is_nil(tenant_id) and is_nil(current_key) ->
        {:error, :no_license_configured}

      true ->
        fetch_and_apply(String.trim_trailing(worker_url, "/"), tenant_id, current_key)
    end
  end

  defp fetch_and_apply(worker_url, tenant_id, current_key) do
    body =
      %{}
      |> then(fn m -> if tenant_id, do: Map.put(m, :tenant_id, tenant_id), else: m end)
      |> then(fn m -> if current_key, do: Map.put(m, :license_key, current_key), else: m end)

    case Req.post("#{worker_url}/api/licenses/verify", json: body, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"valid" => true, "license_key" => fresh_key}}}
      when is_binary(fresh_key) ->
        domain = Application.get_env(:AshPhoenixStarter, :domain)

        with {:ok, claims} <- Verifier.verify(fresh_key, expected_domain: domain) do
          Manager.put(:license_key, fresh_key)
          Manager.put(:plan_tier, claims.tier)
          Application.put_env(:AshPhoenixStarter, :license_key, fresh_key)
          Application.put_env(:AshPhoenixStarter, :plan_tier, claims.tier)

          Phoenix.PubSub.broadcast(
            AshPhoenixStarter.PubSub,
            "tenant:plan",
            {:plan_tier_updated, claims.tier}
          )

          {:ok, Tiers.normalize(claims.tier)}
        end

      {:ok, %{status: 404}} ->
        {:error, :license_not_found}

      {:ok, %{status: status}} ->
        {:error, {:worker_http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_tenant_id(nil), do: nil

  defp extract_tenant_id(key) do
    case Verifier.verify(key) do
      {:ok, %{tenant_id: id}} -> id
      _ -> nil
    end
  end
end
