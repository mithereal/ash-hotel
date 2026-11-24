defmodule AshPhoenixStarter.Telemetry.ClusterReporter do
  @moduledoc """
  Singleton GenServer (supervised by Horde) that aggregates metrics across all
  nodes in a tenant's DigitalOcean cluster and reports them to the central
  Render control plane.
  """
  use GenServer
  require Logger

  @interval :timer.seconds(30)

  def start_link(opts) do
    name =
      Keyword.get(
        opts,
        :name,
        {:via, Horde.Registry, {AshPhoenixStarter.HordeRegistry, __MODULE__}}
      )

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    schedule_report()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:report, state) do
    push_cluster_metrics()
    schedule_report()
    {:noreply, state}
  end

  defp push_cluster_metrics do
    nodes = [Node.self() | Node.list()]
    node_stats = collect_node_stats(nodes)

    payload = %{
      tenant_id: Application.fetch_env!(:AshPhoenixStarter, :tenant_id),
      cluster_size: length(nodes),
      total_memory_bytes: Enum.reduce(node_stats, 0, &(&1.memory_bytes + &2)),
      nodes: node_stats,
      reported_at: DateTime.utc_now()
    }

    control_plane_url = Application.fetch_env!(:AshPhoenixStarter, :control_plane_url)
    api_token = Application.fetch_env!(:AshPhoenixStarter, :control_plane_token)

    case Req.post("#{control_plane_url}/api/clusters/heartbeat",
           json: payload,
           auth: {:bearer, api_token},
           retry: :transient,
           receive_timeout: 5_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("[ClusterReporter] Control plane returned HTTP #{status}")

      {:error, reason} ->
        Logger.warning("[ClusterReporter] Failed to report metrics: #{inspect(reason)}")
    end
  end

  defp collect_node_stats(nodes) do
    results =
      :erpc.multicall(
        nodes,
        fn ->
          %{
            node: Node.self(),
            memory_bytes: :erlang.memory(:total),
            process_count: :erlang.system_info(:process_count),
            scheduler_utilization: :erlang.statistics(:run_queue)
          }
        end,
        3_000
      )

    for {:ok, stat} <- results, do: stat
  end

  defp schedule_report do
    Process.send_after(self(), :report, @interval)
  end
end
