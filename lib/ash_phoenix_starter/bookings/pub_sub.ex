# lib/ash_phoenix_starter/bookings/pub_sub.ex
defmodule AshPhoenixStarter.Bookings.PubSub do
  @moduledoc """
  Tenant-scoped Phoenix.PubSub helpers for real-time booking updates across LiveViews.
  """

  @pubsub AshPhoenixStarter.PubSub

  def subscribe(tenant) when not is_nil(tenant) do
    Phoenix.PubSub.subscribe(@pubsub, topic(tenant))
  end

  def broadcast(tenant, event, booking_id) when not is_nil(tenant) do
    Phoenix.PubSub.broadcast(@pubsub, topic(tenant), {:booking_event, event, booking_id})
  end

  defp topic(tenant), do: "bookings:tenant:#{tenant}"
end
