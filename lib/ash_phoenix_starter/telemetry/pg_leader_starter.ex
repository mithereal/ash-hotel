defmodule AshPhoenixStarter.Telemetry.PgLeaderStarter do
  @moduledoc """
  Acquires a session-level PostgreSQL advisory lock before starting `ControlPlaneClient`.
  Ensures only one container reports telemetry when running multiple stateless containers
  on PaaS providers without private Erlang clustering.
  """
  use GenServer
  require Logger

  alias AshPhoenixStarter.Repo
  alias AshPhoenixStarter.Telemetry.ControlPlaneClient

  # Arbitrary 64-bit integer lock ID unique to ControlPlaneClient
  @lock_id 8_492_017_441_920_114
  @retry_interval :timer.seconds(15)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if Application.get_env(:AshPhoenixStarter, :control_plane_ws_url) do
      send(self(), :try_acquire_lock)
      {:ok, %{child_pid: nil}}
    else
      Logger.info(
        "[PgLeaderStarter] control_plane_ws_url not configured; skipping leader election."
      )

      :ignore
    end
  end

  @impl true
  def handle_info(:try_acquire_lock, %{child_pid: pid} = state) when is_pid(pid) do
    {:noreply, state}
  end

  def handle_info(:try_acquire_lock, state) do
    case Repo.query("SELECT pg_try_advisory_lock($1)", [@lock_id]) do
      {:ok, %{rows: [[true]]}} ->
        Logger.info("[PgLeaderStarter] Acquired advisory lock; starting ControlPlaneClient")

        # Start ControlPlaneClient under this leader process
        case ControlPlaneClient.start_link(name: ControlPlaneClient) do
          {:ok, pid} ->
            Process.monitor(pid)
            {:noreply, %{state | child_pid: pid}}

          {:error, reason} ->
            Logger.error(
              "[PgLeaderStarter] Failed to start ControlPlaneClient: #{inspect(reason)}"
            )

            # Release lock / retry later if startup failed
            Process.send_after(self(), :try_acquire_lock, @retry_interval)
            {:noreply, state}
        end

      {:ok, %{rows: [[false]]}} ->
        # Lock is held by another node/container; retry later
        Process.send_after(self(), :try_acquire_lock, @retry_interval)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning(
          "[PgLeaderStarter] Failed to query advisory lock: #{inspect(reason)}; retrying..."
        )

        Process.send_after(self(), :try_acquire_lock, @retry_interval)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{child_pid: pid} = state) do
    Logger.warning(
      "[PgLeaderStarter] ControlPlaneClient crashed (#{inspect(reason)}); attempting to re-acquire lock..."
    )

    Process.send_after(self(), :try_acquire_lock, 1_000)
    {:noreply, %{state | child_pid: nil}}
  end
end
