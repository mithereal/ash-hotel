defmodule AshPhoenixStarter.Bling do
  @moduledoc """
  Configures Bling for organization-based subscriptions using dynamic gateway settings
  and ties Stripe webhook lifecycle events into application workflows.
  """

  require Logger

  @behaviour Bling

  alias AshPhoenixStarter.Accounts.Checks.Authorize
  alias AshPhoenixStarter.Settings.Billing
  alias AshPhoenixStarter.Settings.Manager
  alias AshPhoenixStarter.Billing.Emails

  @type customer :: Bling.customer()
  @type conn :: Bling.conn()
  @type event :: Stripe.Event.t()

  @doc """
  Determines if the current user context is authorized to manage billing
  for the specified organization organization.
  """
  @impl Bling
  @spec can_manage_billing?(conn(), customer()) :: boolean()
  def can_manage_billing?(_conn, customer) do
    Authorize.can(customer, Billing, :manage)
  end

  def can_manage_billing?(customer) do
    Authorize.can(customer, Billing, :manage)
  end

  # def can_manage_billing?(_conn, _customer), do: false

  @doc """
  Maps a Organization struct to valid Stripe Customer creation parameters,
  attaching the organization_id to Stripe metadata for seamless webhook correlation.
  """
  @impl Bling
  @spec to_stripe_params(customer()) :: map()
  def to_stripe_params(%AshPhoenixStarter.Accounts.Organization{} = organization) do
    %{
      name: organization.name,
      metadata: %{
        "organization_id" => to_string(organization.id),
        "customer_type" => Bling.customer_type_from_struct(organization)
      }
    }
  end

  def to_stripe_params(_customer), do: %{}

  @doc """
  Returns a list of applicable tax rate IDs for the given customer.
  """
  @impl Bling
  @spec tax_rate_ids(customer()) :: [binary()]
  def tax_rate_ids(_customer) do
    []
  end

  @doc """
  Overrides Bling's underlying Stripe request options to pull API keys
  dynamically from the database registry rather than static environment variables.
  """
  @spec stripe_config(customer()) :: keyword()
  def stripe_config(customer) do
    {_, config} = AshPhoenixStarter.Settings.Manager.get_tenant(customer, "stripe")

    [
      api_key: config.secret_key,
      public_key: config.public_key,
      webhook_secret: config.webhook_secret
    ]
  end

  @doc """
  Handles successful invoice payments from Stripe, mapping them
  to your organization and posting ledger entries via ash_double_entry if needed.
  """
  @impl Bling
  @spec handle_stripe_webhook_event(event()) :: any()
  def handle_stripe_webhook_event(%Stripe.Event{type: "invoice.payment_succeeded"} = event) do
    invoice = event.data.object
    organization_id = get_in(invoice, ["metadata", "organization_id"])

    if organization_id do
      IO.inspect(invoice,
        label: "Invoice Payment Succeeded for Organization ID: #{organization_id}"
      )
    end

    {:ok, event}
  end

  def handle_stripe_webhook_event(%Stripe.Event{type: type, data: %{object: obj}})
      when type in [
             "customer.subscription.created",
             "customer.subscription.updated",
             "customer.subscription.deleted"
           ] do
    sync_subscription_to_license_server(obj)
    :ok
  end

  @impl Bling
  def handle_stripe_webhook_event(_event) do
    :ok
  end

  def handle_stripe_webhook_event(%Stripe.Event{
        type: type,
        data: %{object: %Stripe.Invoice{} = invoice}
      })
      when type in ["invoice.payment_action_required", "invoice.payment.failed"] do
    send_payment_failure_email(invoice)
    :ok
  end

  defp send_payment_failure_email(%Stripe.Invoice{} = invoice) do
    case Bling.customer_from_stripe_id(invoice.customer) do
      nil ->
        Logger.warning(
          "[Bling] Received #{invoice.id} for unknown Stripe customer #{invoice.customer}"
        )

      customer ->
        customer_type = Bling.customer_type_from_struct(customer)
        base_url = AshPhoenixStarterWeb.Endpoint.url()

        recovery_url =
          if is_binary(invoice.payment_intent) and invoice.payment_intent != "" do
            "#{base_url}/billing/#{customer_type}/#{customer.id}/finalize?payment_intent=#{invoice.payment_intent}"
          else
            "#{base_url}/settings/billing"
          end

        case Emails.deliver_payment_failed(customer, recovery_url) do
          {:ok, _} ->
            Logger.info("[Bling] Sent payment recovery email to #{customer.email}")

          {:error, reason} ->
            Logger.error("[Bling] Failed to send payment recovery email: #{inspect(reason)}")
        end
    end
  end

  defp sync_subscription_to_license_server(%Stripe.Subscription{} = sub) do
    customer = Bling.customer_from_stripe_id(sub.customer)

    if customer do
      active? = sub.status in ["active", "trialing"]
      tier = if active?, do: "pro", else: "basic"
      tenant_id = to_string(customer.id)
      domain = Map.get(customer, :domain)

      worker_url = Application.get_env(:AshPhoenixStarter, :cloudflare_license_url)
      internal_secret = Application.get_env(:AshPhoenixStarter, :cloudflare_internal_secret)

      if worker_url && internal_secret do
        case Req.post("#{worker_url}/api/licenses/issue",
               json: %{
                 tenant_id: tenant_id,
                 domain: domain,
                 email: customer.email,
                 tier: tier,
                 stripe_customer_id: sub.customer,
                 stripe_subscription_id: sub.id,
                 days_valid: if(active?, do: 40, else: 3650)
               },
               headers: [{"x-internal-secret", internal_secret}],
               receive_timeout: 5_000
             ) do
          {:ok, %{status: 200, body: %{"license_key" => license_key}}} ->
            # Persist the freshly minted Ed25519 key in Settings.Manager
            Manager.put_tenant(tenant_id, :license_key, license_key)
            Manager.put_tenant(tenant_id, :plan_tier, tier)
            :ok

          error ->
            Logger.error(
              "[Bling] Failed to sync license with Cloudflare Worker: #{inspect(error)}"
            )

            :error
        end
      end
    end
  end
end
