defmodule AshPhoenixStarter.Billing.BlingPlanNotifier do
  @moduledoc """
  Ash Notifier that triggers whenever a hotel's Bling subscription is created
  or updated (e.g., tier upgrade from $1/mo to $10/mo).
  """
  use Ash.Notifier

  alias AshPhoenixStarter.Billing.UsageTracker

  @impl Ash.Notifier
  def notify(%Ash.Notifier.Notification{data: subscription, action: %{type: type}})
      when type in [:create, :update] do
    org_id = subscription.organization_id
    region_id = Map.get(subscription, :region_id) || "global"

    if org_id do
      # 1. Flush & restart UsageTracker on its regional OCI node with new plan limits
      UsageTracker.reload_limits(region_id, org_id)

      # 2. Notify any open LiveViews for this hotel via your NotificationHook PubSub topic
      Phoenix.PubSub.broadcast(
        AshPhoenixStarter.PubSub,
        "notifications:org:#{org_id}",
        {:plan_updated, subscription.status}
      )
    end

    :ok
  end

  def notify(_notification), do: :ok
end
