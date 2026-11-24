defmodule AshPhoenixStarter.Telemetry.ControlPlaneClient do
  @moduledoc """
  Persistent Slipstream WebSocket client connecting a self-hosted tenant deployment
  to the Render control plane. Works in both `:standalone` and `:horde` cluster modes.
  """
  use Slipstream
  require Logger

  alias AshPhoenixStarter.Cache.{AppSettings, TenantSettings}
  alias AshPhoenixStarter.Licensing.Verifier
  alias AshPhoenixStarter.Settings.Manager

  @report_interval :timer.seconds(15)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, default_process_name())
    Slipstream.start_link(__MODULE__, opts, name: name)
  end

  defp default_process_name do
    case Application.get_env(:AshPhoenixStarter, :cluster_mode, :standalone) do
      :horde -> {:via, Horde.Registry, {AshPhoenixStarter.HordeRegistry, __MODULE__}}
      _ -> __MODULE__
    end
  end

  @impl Slipstream
  def init(_opts) do
    uri = Application.fetch_env!(:AshPhoenixStarter, :control_plane_ws_url)
    license_key = Application.fetch_env!(:AshPhoenixStarter, :license_key)

    {tenant_id, tier, domain} = resolve_license_identity(license_key)

    config = [
      uri: "#{uri}?token=#{URI.encode_www_form(license_key)}",
      reconnect_after_msec: [1_000, 2_000, 5_000, 10_000, 30_000]
    ]

    socket =
      new_socket()
      |> assign(:tenant_id, tenant_id)
      |> assign(:tier, tier)
      |> assign(:domain, domain)
      |> assign(:topic, "cluster:#{tenant_id}")
      |> connect!(config)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("[ControlPlaneClient] Connected to Render control plane")
    {:ok, join(socket, socket.assigns.topic, %{node: Node.self(), tier: socket.assigns.tier})}
  end

  @impl Slipstream
  def handle_join(topic, _response, socket) do
    Logger.info("[ControlPlaneClient] Joined #{topic}")
    send(self(), :push_metrics)
    {:ok, socket}
  end

  @impl Slipstream
  def handle_disconnect(reason, socket) do
    Logger.warning("[ControlPlaneClient] Disconnected (#{inspect(reason)}), reconnecting...")
    {:ok, reconnect(socket)}
  end

  @impl Slipstream
  def handle_info(:push_metrics, socket) do
    if connected?(socket) do
      payload = gather_cluster_metrics(socket.assigns)
      push(socket, socket.assigns.topic, "metrics:report", payload)
    end

    Process.send_after(self(), :push_metrics, @report_interval)
    {:noreply, socket}
  end

  @impl Slipstream
  def handle_message(topic, "command:set_tier", %{"tier" => tier} = params, socket)
      when tier in ["basic", "pro"] do
    Logger.info("[ControlPlaneClient] Live tier update received: #{tier}")

    Manager.put(:plan_tier, tier)
    Application.put_env(:AshPhoenixStarter, :plan_tier, tier)

    if new_key = params["license_key"] do
      Manager.put(:license_key, new_key)
      Application.put_env(:AshPhoenixStarter, :license_key, new_key)
    end

    Phoenix.PubSub.broadcast(AshPhoenixStarter.PubSub, "tenant:plan", {:plan_tier_updated, tier})
    push(socket, topic, "command:ack", %{command: "set_tier", tier: tier, status: "ok"})

    {:ok, assign(socket, :tier, tier)}
  end

  def handle_message(topic, "command:clear_cache", _payload, socket) do
    AppSettings.delete_all()
    TenantSettings.delete_all()
    push(socket, topic, "command:ack", %{command: "clear_cache", status: "ok"})
    {:ok, socket}
  end

  def handle_message(_topic, _event, _payload, socket), do: {:ok, socket}

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp resolve_license_identity(license_key) do
    configured_domain =
      Application.get_env(:AshPhoenixStarter, :domain) || System.get_env("PHX_HOST")

    case Verifier.verify(license_key, expected_domain: configured_domain) do
      {:ok, claims} ->
        Manager.put(:plan_tier, claims.tier)
        {claims.tenant_id, claims.tier, claims.domain || configured_domain}

      {:error, reason} ->
        Logger.warning(
          "[ControlPlaneClient] License verification fallback (#{reason}), using basic tier"
        )

        fallback_id = Application.get_env(:AshPhoenixStarter, :tenant_id) || "unlicensed"
        {fallback_id, "basic", configured_domain}
    end
  end

  defp gather_cluster_metrics(assigns) do
    nodes = [Node.self() | Node.list()]

    {results, _bad} =
      :erpc.multicall(
        nodes,
        fn ->
          %{
            node: to_string(Node.self()),
            memory_bytes: :erlang.memory(:total),
            process_count: :erlang.system_info(:process_count),
            run_queue: :erlang.statistics(:run_queue)
          }
        end,
        3_000
      )

    node_stats = for {:ok, stat} <- results, do: stat

    %{
      tenant_id: assigns.tenant_id,
      domain: assigns.domain,
      tier: assigns.tier,
      cluster_mode:
        to_string(Application.get_env(:AshPhoenixStarter, :cluster_mode, :standalone)),
      cluster_size: length(node_stats),
      total_memory_bytes: Enum.reduce(node_stats, 0, &(&1.memory_bytes + &2)),
      total_processes: Enum.reduce(node_stats, 0, &(&1.process_count + &2)),
      nodes: node_stats,
      reported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
