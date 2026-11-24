defmodule AshPhoenixStarterWeb.Billing.CheckoutComponent do
  @moduledoc """
  Stateful LiveComponent that lets users pick a subscription tier (`:plus`, `:pro`, `:enterprise`),
  select an enabled payment provider, or activate an offline Ed25519 license key.
  """

  use AshPhoenixStarterWeb, :live_component

  alias AshPhoenixStarter.Billing
  alias AshPhoenixStarter.Billing.{Registry, Tiers}
  alias AshPhoenixStarter.Licensing.Verifier
  alias AshPhoenixStarter.Settings.Manager

  @plans [
    %{
      id: :plus,
      name: "Plus",
      price: "$19",
      interval: "/mo",
      badge: nil,
      description: "For growing organizations needing custom storage and API access.",
      highlights: [
        "Up to 5 organizations & 15 organization members",
        "Custom S3 / R2 / DigitalOcean Spaces storage",
        "Custom domains & API access (150 MB uploads)"
      ]
    },
    %{
      id: :pro,
      name: "Pro",
      price: "$49",
      interval: "/mo",
      badge: "Most Popular",
      description: "Full horizontal scale-out and advanced analytics.",
      highlights: [
        "Multi-node Horde clustering (up to 10 nodes)",
        "Up to 25 organizations & 100 organization members",
        "Advanced analytics & 500 MB uploads"
      ]
    },
    %{
      id: :enterprise,
      name: "Enterprise",
      price: "$149",
      interval: "/mo",
      badge: nil,
      description: "Unlimited scale, white-labeling, and dedicated support.",
      highlights: [
        "Unlimited Horde cluster nodes & organizations",
        "White-label branding & 2 GB file uploads",
        "Dedicated priority engineering support"
      ]
    }
  ]

  @impl true
  def update(assigns, socket) do
    providers = Registry.enabled_providers()
    default_provider = providers |> List.first() |> then(&(&1 && &1.id))
    customer = assigns[:current_user]
    current_tier = Billing.current_tier(customer)

    requested_tier =
      case assigns[:target_tier] do
        nil -> next_upgrade_tier(current_tier)
        tier -> Tiers.normalize(tier)
      end

    worker_url = Application.get_env(:AshPhoenixStarter, :cloudflare_license_url)

    recover_url =
      if is_binary(worker_url) and worker_url != "" do
        "#{String.trim_trailing(worker_url, "/")}/api/licenses/recover"
      else
        nil
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:plans, @plans)
      |> assign(:current_tier, current_tier)
      |> assign(:providers, providers)
      |> assign(:has_managed_sub, has_active_subscription?(customer))
      |> assign(:recover_url, recover_url)
      |> assign_new(:selected_tier, fn -> requested_tier end)
      |> assign_new(:selected_provider, fn -> default_provider end)
      |> assign_new(:license_input, fn -> "" end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:portal_loading, fn -> false end)
      |> assign_new(:error_message, fn -> nil end)
      |> assign_new(:success_message, fn -> nil end)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_tier", %{"tier" => tier_str}, socket) do
    tier = Tiers.normalize(tier_str)

    if tier in [:plus, :pro, :enterprise] do
      {:noreply,
       socket
       |> assign(:selected_tier, tier)
       |> assign(:error_message, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_provider", %{"provider" => provider_str}, socket) do
    provider_atom = String.to_existing_atom(provider_str)

    if Registry.enabled?(provider_atom) do
      {:noreply,
       socket
       |> assign(:selected_provider, provider_atom)
       |> assign(:error_message, nil)}
    else
      {:noreply,
       assign(socket, :error_message, "Selected payment provider is no longer available.")}
    end
  end

  @impl true
  def handle_event("start_checkout", _params, socket) do
    provider = socket.assigns.selected_provider
    tier = socket.assigns.selected_tier
    customer = socket.assigns.current_user
    success_url = socket.assigns[:success_url] || "/settings/billing?upgraded=true"

    socket = assign(socket, loading: true, error_message: nil)

    case start_provider_checkout(provider, tier, customer, success_url) do
      {:ok, checkout_url} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, :provider_disabled} ->
        {:noreply,
         socket
         |> assign(loading: false, providers: Registry.enabled_providers())
         |> assign(
           :error_message,
           "That payment method was recently disabled. Please choose another."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(loading: false)
         |> assign(:error_message, "Unable to start checkout: #{format_error(reason)}")}
    end
  end

  @impl true
  def handle_event("open_portal", _params, socket) do
    customer = socket.assigns.current_user
    return_url = socket.assigns[:success_url] || "/settings/billing"

    socket = assign(socket, portal_loading: true, error_message: nil)

    case Billing.portal_url(customer, return_url) do
      {:ok, url} ->
        {:noreply, redirect(socket, external: url)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:portal_loading, false)
         |> assign(:error_message, "Unable to open billing portal right now. Please try again.")}
    end
  end

  @impl true
  def handle_event("activate_license", %{"license_key" => raw_key}, socket) do
    trimmed_key = String.trim(raw_key)
    domain = Application.get_env(:AshPhoenixStarter, :domain)

    case Verifier.verify(trimmed_key, expected_domain: domain) do
      {:ok, claims} ->
        Manager.put(:license_key, trimmed_key)
        Manager.put(:plan_tier, claims.tier)
        Application.put_env(:AshPhoenixStarter, :license_key, trimmed_key)
        Application.put_env(:AshPhoenixStarter, :plan_tier, claims.tier)

        Phoenix.PubSub.broadcast(
          AshPhoenixStarter.PubSub,
          "tenant:plan",
          {:plan_tier_updated, claims.tier}
        )

        new_tier = Tiers.normalize(claims.tier)

        {:noreply,
         socket
         |> assign(:current_tier, new_tier)
         |> assign(:license_input, "")
         |> assign(:error_message, nil)
         |> assign(:success_message, "Activated #{Tiers.label(new_tier)} license key!")}

      {:error, :domain_mismatch} ->
        {:noreply,
         assign(
           socket,
           :error_message,
           "This license key is registered to a different domain than #{domain}."
         )}

      {:error, :license_expired} ->
        {:noreply, assign(socket, :error_message, "This license key has expired.")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error_message, "Invalid license key signature or format.")}
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp next_upgrade_tier(:basic), do: :pro
  defp next_upgrade_tier(:plus), do: :pro
  defp next_upgrade_tier(:pro), do: :enterprise
  defp next_upgrade_tier(:enterprise), do: :enterprise

  defp start_provider_checkout(:stripe, tier, customer, success_url) do
    if Registry.enabled?(:stripe) do
      price_key = String.to_existing_atom("#{tier}_monthly")
      price_id = Application.fetch_env!(:bling, :prices)[price_key]

      case Bling.Customers.create_subscription(customer,
             plan: Atom.to_string(tier),
             return_url: success_url,
             prices: [{price_id, 1}]
           ) do
        {:ok, _subscription} ->
          {:ok, success_url}

        {:requires_action, _payment_intent} ->
          type = Bling.customer_type_from_struct(customer)
          {:ok, "/billing/#{type}/#{customer.id}/finalize"}

        {:error, %{user_message: msg}} ->
          {:error, msg}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :provider_disabled}
    end
  end

  defp start_provider_checkout(provider, tier, customer, success_url) do
    Billing.checkout_url(provider, customer, tier: tier, success_url: success_url)
  end

  defp has_active_subscription?(nil), do: false

  defp has_active_subscription?(customer) do
    sub_schema = Application.fetch_env!(:bling, :subscription)

    not is_nil(
      AshPhoenixStarter.Repo.get_by(sub_schema, customer_id: customer.id, status: "active")
    )
  end

  defp format_error(msg) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  # ============================================================================
  # TEMPLATE
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Active Plan Banner & Portal Button --%>
      <div class="flex flex-col gap-4 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div class="flex items-center gap-2.5">
            <span class="text-sm font-medium text-zinc-500">Current Plan:</span>
            <span class="inline-flex items-center rounded-full bg-indigo-50 px-3 py-0.5 text-xs font-semibold uppercase text-indigo-700">
              {Tiers.label(@current_tier)}
            </span>
          </div>
          <p class="mt-1 text-sm text-zinc-500">
            <%= if @current_tier == :basic do %>
              Choose a plan below to unlock custom storage, horizontal Horde scaling, and higher limits.
            <% else %>
              Upgrade anytime below or manage your existing subscription, invoices, and payment method.
            <% end %>
          </p>
        </div>

        <.button
          :if={@has_managed_sub}
          phx-click="open_portal"
          phx-target={@myself}
          disabled={@portal_loading}
          class="inline-flex shrink-0 items-center justify-center rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm font-semibold text-zinc-900 shadow-sm hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {if @portal_loading, do: "Opening Portal...", else: "Manage Subscription"}
        </.button>
      </div>

      <%!-- Error / Success Banners --%>
      <div
        :if={@error_message}
        class="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700"
      >
        {@error_message}
      </div>

      <div
        :if={@success_message}
        class="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800"
      >
        {@success_message}
      </div>

      <%!-- Step 1: Tier Selection Cards --%>
      <div class="space-y-3">
        <label class="block text-xs font-semibold uppercase tracking-wide text-zinc-500">
          1. Select Plan Tier
        </label>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <%= for plan <- @plans do %>
            <% is_current? = @current_tier == plan.id %>
            <% is_lower? = Tiers.at_least?(@current_tier, plan.id) and not is_current? %>
            <% selected? = @selected_tier == plan.id and not is_current? and not is_lower? %>

            <div
              phx-click={unless(is_current? or is_lower?, do: "select_tier")}
              phx-value-tier={plan.id}
              phx-target={@myself}
              class={[
                "relative flex flex-col justify-between rounded-2xl border p-6 transition",
                cond do
                  is_current? ->
                    "border-emerald-300 bg-emerald-50/30"

                  is_lower? ->
                    "border-zinc-200 bg-zinc-50 opacity-60"

                  selected? ->
                    "cursor-pointer border-indigo-600 bg-indigo-50/30 ring-2 ring-indigo-600"

                  true ->
                    "cursor-pointer border-zinc-200 bg-white hover:border-zinc-300"
                end
              ]}
            >
              <div>
                <div class="flex items-center justify-between">
                  <span class="text-lg font-bold text-zinc-900">{plan.name}</span>
                  <%= if is_current? do %>
                    <span class="rounded-full bg-emerald-100 px-2.5 py-0.5 text-xs font-semibold text-emerald-800">
                      Current Plan
                    </span>
                  <% else %>
                    <span
                      :if={plan.badge}
                      class="rounded-full bg-indigo-100 px-2.5 py-0.5 text-xs font-semibold text-indigo-700"
                    >
                      {plan.badge}
                    </span>
                  <% end %>
                </div>

                <div class="mt-4 flex items-baseline gap-1">
                  <span class="text-3xl font-extrabold text-zinc-900">{plan.price}</span>
                  <span class="text-sm text-zinc-500">{plan.interval}</span>
                </div>

                <p class="mt-2 text-sm text-zinc-600">{plan.description}</p>

                <ul class="mt-6 space-y-2.5 text-sm text-zinc-600">
                  <%= for item <- plan.highlights do %>
                    <li class="flex items-start gap-2">
                      <span class="font-bold text-indigo-600">✓</span>
                      <span>{item}</span>
                    </li>
                  <% end %>
                </ul>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Step 2: Payment Provider Selection --%>
      <div
        :if={@current_tier != :enterprise}
        class="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm space-y-6"
      >
        <label class="block text-xs font-semibold uppercase tracking-wide text-zinc-500">
          2. Select Payment Method
        </label>

        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <%= for provider <- @providers do %>
            <% selected? = @selected_provider == provider.id %>
            <button
              phx-click="select_provider"
              phx-value-provider={provider.id}
              phx-target={@myself}
              class={[
                "flex items-center justify-between rounded-xl border p-4 text-left transition",
                if(selected?,
                  do: "border-indigo-600 bg-indigo-50/40 ring-1 ring-indigo-600",
                  else: "border-zinc-200 hover:border-indigo-500 hover:bg-zinc-50/50"
                )
              ]}
            >
              <div>
                <div class="font-semibold text-zinc-900">{provider.name}</div>
                <div class="text-xs text-zinc-500">{provider.label}</div>
              </div>

              <div class={[
                "mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border",
                if(selected?, do: "border-indigo-600 bg-indigo-600", else: "border-zinc-300")
              ]}>
                <span
                  :if={provider.badge}
                  class="rounded-full bg-indigo-50 px-2.5 py-0.5 text-xs font-medium text-indigo-700"
                >
                  {provider.badge}
                </span>

                <div :if={selected?} class="h-1.5 w-1.5 rounded-full bg-white"></div>
              </div>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Proceed Checkout Button --%>
      <.button
        phx-click="start_checkout"
        phx-target={@myself}
        disabled={
          @loading or is_nil(@selected_provider) or Tiers.at_least?(@current_tier, @selected_tier)
        }
        class="inline-flex w-full items-center justify-center rounded-xl bg-indigo-600 px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-50"
      >
        <%= if @loading do %>
          Redirecting to checkout...
        <% else %>
          Upgrade to {Tiers.label(@selected_tier)}
        <% end %>
      </.button>

      <%!-- Step 3: Offline License Key Activation & Recovery --%>
      <div class="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm space-y-4">
        <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h4 class="text-sm font-semibold text-zinc-900">Already have a license key?</h4>
            <p class="text-xs text-zinc-500">
              Paste your signed license key below to activate or upgrade this instance immediately.
            </p>
          </div>

          <a
            :if={@recover_url}
            href={@recover_url}
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs font-semibold text-indigo-600 hover:text-indigo-500"
          >
            Lost your license key? &rarr;
          </a>
        </div>

        <form
          phx-submit="activate_license"
          phx-target={@myself}
          class="flex flex-col gap-3 sm:flex-row"
        >
          <input
            type="text"
            name="license_key"
            value={@license_input}
            placeholder="eyJ0ZW5hbnRfaWQiOi... (paste signed license key)"
            required
            class="block w-full rounded-xl border border-zinc-300 px-3.5 py-2 text-xs font-mono text-zinc-900 placeholder:text-zinc-400 focus:border-indigo-600 focus:outline-none focus:ring-1 focus:ring-indigo-600"
          />
          <.button class="inline-flex shrink-0 items-center justify-center rounded-xl bg-zinc-900 px-4 py-2 text-xs font-semibold text-white shadow-sm hover:bg-zinc-700">
            Activate Key
          </.button>
        </form>
      </div>
    </div>
    """
  end
end
