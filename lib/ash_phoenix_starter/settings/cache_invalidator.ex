defmodule AshPhoenixStarter.Settings.CacheInvalidator do
  @moduledoc """
  Listens for cross-node setting updates and evicts stale local Nebulex cache keys
  when running in a multi-node cluster.
  """
  use GenServer

  @pubsub AshPhoenixStarter.PubSub
  @topic "ash_phoenix_starter:settings:invalidation"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:invalidate_cache, cache_module, key}, state) do
    # Nebulex delete takes the key directly
    cache_module.delete(key)
    {:noreply, state}
  end
end
