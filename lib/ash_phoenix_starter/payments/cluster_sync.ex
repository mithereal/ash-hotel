defmodule Hotel.Payments.ClusterSync do
  use GenServer
  require Logger

  alias Hotel.Payments.PluginLoader

  @topic "hotel:payment_plugins:sync"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    backend = cluster_backend()

    # Always hydrate local ETS Registry from Postgres on boot
    PluginLoader.load_persisted_plugins()

    case backend do
      :pubsub ->
        Phoenix.PubSub.subscribe(Hotel.PubSub, @topic)

      :horde ->
        :net_kernel.monitor_nodes(true)
        Phoenix.PubSub.subscribe(Hotel.PubSub, @topic)

      :local ->
        :ok
    end

    {:ok, %{backend: backend}}
  end

  @doc """
  Broadcasts a newly installed plugin to peer nodes according to the configured cluster backend.
  """
  def broadcast_plugin_installed(runtime, mod_str, payload, sig_b64) do
    case cluster_backend() do
      :local ->
        :ok

      :pubsub ->
        Phoenix.PubSub.broadcast(
          Hotel.PubSub,
          @topic,
          {:load_plugin, node(), runtime, mod_str, payload, sig_b64}
        )

      :horde ->
        # Sync directly across all Horde cluster members via :erpc, with PubSub fallback
        peers = horde_peer_nodes()

        if peers != [] do
          :erpc.multicall(
            peers,
            __MODULE__,
            :remote_load_plugin,
            [runtime, mod_str, payload, sig_b64],
            5_000
          )
        end
    end
  end

  @doc false
  def remote_load_plugin(runtime, mod_str, payload, sig_b64) do
    case PluginLoader.verify_and_load(runtime, mod_str, payload, sig_b64) do
      {:ok, meta} ->
        Logger.info("[ClusterSync] Loaded plugin #{meta.id} (#{runtime}) on #{node()}")
        {:ok, meta.id}

      {:error, reason} ->
        Logger.error("[ClusterSync] Failed loading plugin on #{node()}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- PubSub & Node Monitoring Callbacks ---

  @impl true
  def handle_info({:load_plugin, origin_node, runtime, mod_str, payload, sig_b64}, state) do
    if origin_node != node() do
      remote_load_plugin(runtime, mod_str, payload, sig_b64)
    end

    {:noreply, state}
  end

  def handle_info({:nodeup, new_node}, %{backend: :horde} = state) do
    Logger.info("[ClusterSync] Node #{new_node} joined Horde cluster; ensuring plugins hydrated")
    :erpc.cast(new_node, PluginLoader, :load_persisted_plugins, [])
    {:noreply, state}
  end

  def handle_info({:nodedown, _node}, state), do: {:noreply, state}

  # --- Helpers ---

  defp cluster_backend do
    Application.get_env(:hotel, :cluster_backend, :pubsub)
  end

  defp horde_peer_nodes do
    if Code.ensure_loaded?(Horde.Cluster) do
      Horde.Cluster.members(Hotel.Payments.HordeSupervisor)
      |> Enum.map(fn {_name, member_node} -> member_node end)
      |> Enum.reject(&(&1 == node()))
    else
      Node.list()
    end
  end
end
