defmodule AshPhoenixStarter.ClusterTopologyObserver do
  @moduledoc """
  Listens for Erlang cluster topology changes and updates Horde registry and
  supervisor memberships dynamically.
  """
  use GenServer
  require Logger

  @horde_processes [
    AshPhoenixStarter.HordeRegistry,
    AshPhoenixStarter.HordeSupervisor,
    AshPhoenixStarter.Bookings.HandlerRegistry
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true)
    send(self(), :sync_horde)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("▶️ [Cluster Scale Ingress] Node joined mesh: #{node}")
    synchronize_distributed_horde_topologies()
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.warning("⚠️ [Cluster Scale Egress] Node dropped offline: #{node}")
    synchronize_distributed_horde_topologies()
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync_horde, state) do
    synchronize_distributed_horde_topologies()
    {:noreply, state}
  end

  defp synchronize_distributed_horde_topologies do
    active_nodes = [Node.self() | Node.list()]

    Logger.info(
      "🔄 [Horde Sync] Node #{Node.self()} aligning topology for nodes: #{inspect(active_nodes)}"
    )

    Enum.each(@horde_processes, fn process_name ->
      members = Enum.map(active_nodes, fn node -> {process_name, node} end)
      safe_set_members(process_name, members)
    end)
  end

  defp safe_set_members(cluster_name, members) do
    case Horde.Cluster.set_members(cluster_name, members) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "❌ [Horde Sync Failed] Unable to set membership topology for #{inspect(cluster_name)}: #{inspect(reason)}"
        )
    end
  end
end
