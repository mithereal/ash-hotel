defmodule AshPhoenixStarter.Bling.LicenseSync do
  @moduledoc """
  Shared helper that calls the Cloudflare Worker license server to mint an
  Ed25519 license key whenever a subscription changes in Stripe, Polar, or Lemon Squeezy.
  """
  require Logger
  alias AshPhoenixStarter.Settings.Manager

  def sync(%{tenant_id: tenant_id, tier: tier} = params) do
    worker_url = Application.get_env(:AshPhoenixStarter, :cloudflare_license_url)
    internal_secret = Application.get_env(:AshPhoenixStarter, :cloudflare_internal_secret)

    if worker_url && internal_secret do
      payload = %{
        tenant_id: tenant_id,
        domain: params[:domain],
        email: params[:email],
        tier: tier,
        provider: params[:provider],
        stripe_customer_id: params[:external_customer_id],
        stripe_subscription_id: params[:external_subscription_id],
        days_valid: if(tier == "pro", do: 40, else: 3650)
      }

      case Req.post("#{worker_url}/api/licenses/issue",
             json: payload,
             headers: [{"x-internal-secret", internal_secret}],
             receive_timeout: 5_000
           ) do
        {:ok, %{status: 200, body: %{"license_key" => license_key}}} ->
          Manager.put_tenant(tenant_id, :license_key, license_key)
          Manager.put_tenant(tenant_id, :plan_tier, tier)
          {:ok, license_key}

        error ->
          Logger.error("[LicenseSync] Cloudflare license sync failed: #{inspect(error)}")
          {:error, error}
      end
    else
      :ok
    end
  end
end
