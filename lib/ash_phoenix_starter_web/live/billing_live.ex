defmodule AshPhoenixStarterWeb.BillingLive do
  use AshPhoenixStarterWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AshPhoenixStarter.PubSub, "tenant:plan")
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:plan_tier_updated, _tier}, socket) do
    # Re-render CheckoutComponent with updated Pro status
    send_update(AshPhoenixStarterWeb.Billing.CheckoutComponent,
      id: "pro-checkout",
      current_user: socket.assigns.current_user
    )

    {:noreply, put_flash(socket, :info, "Your Pro subscription is now active!")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-4 py-10">
      <.live_component
        module={AshPhoenixStarterWeb.Billing.CheckoutComponent}
        id="pro-checkout"
        current_user={@current_user}
        success_url={url(~p"/settings/billing?upgraded=true")}
      />
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <%= for provider <- AshPhoenixStarter.Billing.Registry.enabled_providers() do %>
          <.button
            phx-click="start_checkout"
            phx-value-provider={provider.id}
            class="flex items-center justify-between rounded-xl border border-zinc-200 p-4 text-left hover:border-indigo-500"
          >
            <div>
              <div class="font-semibold text-zinc-900">{provider.name}</div>
              <div class="text-xs text-zinc-500">{provider.label}</div>
            </div>
            <span
              :if={provider.badge}
              class="rounded-full bg-indigo-50 px-2.5 py-0.5 text-xs font-medium text-indigo-700"
            >
              {provider.badge}
            </span>
          </.button>
        <% end %>
      </div>
    </div>
    """
  end
end
