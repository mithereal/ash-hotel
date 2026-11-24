defmodule AshPhoenixStarter.Billing.UsageTracker do
  @moduledoc """
  Horde-supervised GenServer that tracks storage and bandwidth per hotel (`org_id`)
  and region (`region_id`) across your OCI cluster.
  """
  use GenServer
  require Logger

  # Flush counters to Postgres every 60 seconds
  @flush_interval :timer.seconds(60)

  # Default monthly limits for $1-$10/mo tiers (customize per plan)
  # 5 GB
  @default_storage_limit 5 * 1024 * 1024 * 1024
  # 50 GB
  @default_bandwidth_limit 50 * 1024 * 1024 * 1024

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc """
  Checks if a hotel has enough remaining storage quota before allowing an upload.
  Called automatically by `ImageUploader` and `StorageDispatcher`.
  """
  def allow_storage?(region_id, org_id, incoming_bytes) do
    pid = ensure_started(region_id, org_id)
    GenServer.call(pid, {:allow_storage?, incoming_bytes})
  end

  @doc """
  Checks if a hotel has exceeded its monthly guest viewing bandwidth.
  Pass the result to `ImageUploader.url(..., quota_exceeded?: exceeded?)`.
  """
  def bandwidth_exceeded?(region_id, org_id) do
    pid = ensure_started(region_id, org_id)
    GenServer.call(pid, :bandwidth_exceeded?)
  end

  @doc """
  Records storage or bandwidth delta in memory (non-blocking).
  """
  def record_usage(region_id, org_id, type, bytes) when type in [:storage, :bandwidth] do
    pid = ensure_started(region_id, org_id)
    GenServer.cast(pid, {:record, type, bytes})
  end

  # ============================================================================
  # HORDE PROCESS LOOKUP & STARTUP
  # ============================================================================

  def ensure_started(region_id, org_id) do
    name = via_tuple(region_id, org_id)

    case Horde.Registry.lookup(AshPhoenixStarter.HordeRegistry, {region_id, org_id}) do
      [{pid, _}] ->
        pid

      [] ->
        spec = {__MODULE__, %{region_id: region_id, org_id: org_id, name: name}}

        case Horde.DynamicSupervisor.start_child(AshPhoenixStarter.HordeSupervisor, spec) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
    end
  end

  @doc """
  Stops the active tracker so Horde restarts it with updated Bling plan limits
  on the hotel's next request (flushes pending usage first via terminate/2).
  """
  def reload_limits(region_id, org_id) do
    case Horde.Registry.lookup(AshPhoenixStarter.HordeRegistry, {region_id, org_id}) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  defp via_tuple(region_id, org_id) do
    {:via, Horde.Registry, {AshPhoenixStarter.HordeRegistry, {region_id, org_id}}}
  end

  def start_link(%{name: name} = args) do
    GenServer.start_link(__MODULE__, args, name: name)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(%{region_id: region_id, org_id: org_id}) do
    schedule_flush()
    Process.flag(:trap_exit, true)
    # Load current monthly totals & plan limits from Postgres on startup
    {storage_used, bandwidth_used, storage_limit, bandwidth_limit} =
      load_from_db(region_id, org_id)

    {:ok,
     %{
       region_id: region_id,
       org_id: org_id,
       storage_used: storage_used,
       bandwidth_used: bandwidth_used,
       pending_storage_delta: 0,
       pending_bandwidth_delta: 0,
       storage_limit: storage_limit,
       bandwidth_limit: bandwidth_limit,
       alert_level: initial_alert_level(bandwidth_used, bandwidth_limit)
     }}
  end

  @impl true
  def handle_call({:allow_storage?, incoming_bytes}, _from, state) do
    allowed? = state.storage_used + incoming_bytes <= state.storage_limit
    {:reply, allowed?, state}
  end

  @impl true
  def handle_call(:bandwidth_exceeded?, _from, state) do
    exceeded? = state.bandwidth_used >= state.bandwidth_limit
    {:reply, exceeded?, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      region_id: state.region_id,
      org_id: state.org_id,
      node: node(),
      storage_used: state.storage_used,
      storage_limit: state.storage_limit,
      bandwidth_used: state.bandwidth_used,
      bandwidth_limit: state.bandwidth_limit,
      alert_level: state.alert_level
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:record, :storage, bytes}, state) do
    {:noreply,
     %{
       state
       | storage_used: max(0, state.storage_used + bytes),
         pending_storage_delta: state.pending_storage_delta + bytes
     }}
  end

  @impl true
  def handle_cast({:record, :bandwidth, bytes}, state) do
    new_bandwidth = max(0, state.bandwidth_used + bytes)
    new_alert_level = maybe_broadcast_quota_alert(state, new_bandwidth)

    {:noreply,
     %{
       state
       | bandwidth_used: new_bandwidth,
         pending_bandwidth_delta: state.pending_bandwidth_delta + bytes,
         alert_level: new_alert_level
     }}
  end

  defp initial_alert_level(used, limit) when limit > 0 do
    ratio = used / limit

    cond do
      ratio >= 1.0 -> :capped_100
      ratio >= 0.8 -> :warn_80
      true -> :none
    end
  end

  defp initial_alert_level(_, _), do: :none

  defp maybe_broadcast_quota_alert(%{bandwidth_limit: limit}, _new_used) when limit <= 0,
    do: :none

  defp maybe_broadcast_quota_alert(state, new_used) do
    ratio = new_used / state.bandwidth_limit

    cond do
      ratio >= 1.0 and state.alert_level != :capped_100 ->
        broadcast_warning(state.org_id, 100)
        :capped_100

      ratio >= 0.8 and state.alert_level == :none ->
        broadcast_warning(state.org_id, 80)
        :warn_80

      true ->
        state.alert_level
    end
  end

  defp broadcast_warning(org_id, percent) do
    Phoenix.PubSub.broadcast(
      AshPhoenixStarter.PubSub,
      "notifications:org:#{org_id}",
      {:quota_warning, percent}
    )
  end

  @impl true
  def terminate(_reason, state) do
    if state.pending_storage_delta != 0 or state.pending_bandwidth_delta != 0 do
      flush_to_db(state)
    end

    :ok
  end

  @impl true
  def handle_info(:flush_to_db, state) do
    schedule_flush()

    if state.pending_storage_delta != 0 or state.pending_bandwidth_delta != 0 do
      flush_to_db(state)
    end

    {:noreply, %{state | pending_storage_delta: 0, pending_bandwidth_delta: 0}}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush_to_db, @flush_interval)
  end

  # ============================================================================
  # DATABASE HOOKS (REPLACE WITH YOUR ASH RESOURCE CALLS)
  # ============================================================================

  alias AshPhoenixStarter.Billing.TenantUsage

  alias AshPhoenixStarter.Accounts.Organization
  alias AshPhoenixStarter.Billing.{PlanLimits, TenantUsage}

  defp load_from_db(region_id, org_id) do
    period_start = Date.beginning_of_month(Date.utc_today())
    region_str = to_string(region_id)

    case read_usage_period(org_id, region_str, period_start) do
      {:ok, %TenantUsage{} = current} ->
        {
          current.storage_bytes,
          current.bandwidth_bytes,
          current.storage_limit_bytes,
          current.bandwidth_limit_bytes
        }

      _ ->
        # New billing month: reset bandwidth to 0, but carry forward active object storage
        # and custom plan limits from the previous billing period
        carry_forward_state(org_id, region_str, period_start)
    end
  end

  defp carry_forward_state(org_id, region_str, new_period_start) do
    case TenantUsage
         |> Ash.Query.for_read(:latest_for_tenant, %{
           organization_id: org_id,
           region_id: region_str
         })
         |> Ash.read_one(authorize?: false) do
      {:ok, %TenantUsage{} = prev} ->
        TenantUsage
        |> Ash.Changeset.for_create(
          :seed_new_period,
          %{
            organization_id: org_id,
            region_id: region_str,
            period_start: new_period_start,
            storage_bytes: prev.storage_bytes,
            storage_limit_bytes: prev.storage_limit_bytes,
            bandwidth_limit_bytes: prev.bandwidth_limit_bytes
          },
          authorize?: false
        )
        |> Ash.create()

        {prev.storage_bytes, 0, prev.storage_limit_bytes, prev.bandwidth_limit_bytes}

      _ ->
        {s_lim, b_lim} = resolve_plan_limits(org_id)
        {0, 0, s_lim, b_lim}
    end
  end

  defp read_usage_period(org_id, region_str, period_start) do
    TenantUsage
    |> Ash.Query.for_read(:for_current_period, %{
      organization_id: org_id,
      region_id: region_str,
      period_start: period_start
    })
    |> Ash.read_one(authorize?: false)
  end

  defp resolve_plan_limits(org_id) do
    # Loads active Bling subscription relationship from your Organization resource
    case Ash.get(Organization, org_id, load: [:subscriptions], authorize?: false) do
      {:ok, %{subscriptions: subs}} when is_list(subs) ->
        active_sub = Enum.find(subs, &(&1.status in ["active", "trialing"]))
        price_id = active_sub && active_sub.stripe_price_id
        PlanLimits.limits_for_price(price_id)

      _ ->
        PlanLimits.limits_for_price(nil)
    end
  end

  defp flush_to_db(state) do
    period_start = Date.beginning_of_month(Date.utc_today())

    TenantUsage
    |> Ash.Changeset.for_create(
      :record_delta,
      %{
        organization_id: state.org_id,
        region_id: to_string(state.region_id),
        period_start: period_start,
        storage_delta: state.pending_storage_delta,
        bandwidth_delta: state.pending_bandwidth_delta
      },
      authorize?: false
    )
    |> Ash.create()
  end

  @doc """
  Queries all active `UsageTracker` processes across your OCI cluster via Horde
  and returns a list of live usage maps per hotel and region.
  """
  def cluster_stats do
    Horde.Registry.select(AshPhoenixStarter.HordeRegistry, [
      {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.flat_map(fn
      {{_region_id, _org_id}, pid} when is_pid(pid) ->
        try do
          [GenServer.call(pid, :get_stats, 1_000)]
        catch
          :exit, _ -> []
        end

      _ ->
        []
    end)
  end
end
