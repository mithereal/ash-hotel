defmodule AshPhoenixStarter.Application do
  @moduledoc """
    2. On each OCI VM, set its RELEASE_NODE environment variable using the app_<region>@<ip> convention so Horde knows which region that VM belongs to:
  	• US Ashburn VM: RELEASE_NODE=app_us_ashburn_1@10.0.1.10
  	• EU Frankfurt VM: RELEASE_NODE=app_eu_frankfurt_1@10.0.2.10
  """

  use Application

  alias AshPhoenixStarter.Cache.{AppSettings, TenantSettings, TimezoneResolution}

  @impl true
  def start(_type, _args) do
    # Attach billing/storage telemetry listeners before starting children
    AshPhoenixStarter.Billing.TelemetryHandler.attach()

    topologies = Application.get_env(:libcluster, :topologies, [])

    children =
      timezone_cache_children() ++
        [
          Cldr.Currency,
          AshPhoenixStarterWeb.Telemetry,
          AshPhoenixStarter.Repo,
          {Cluster.Supervisor, [topologies, [name: AshPhoenixStarter.ClusterSupervisor]]},
          {Phoenix.PubSub, name: AshPhoenixStarter.PubSub},
          {Horde.Registry,
           [name: AshPhoenixStarter.HordeRegistry, keys: :unique, members: :auto]},
          {Horde.DynamicSupervisor,
           [
             name: AshPhoenixStarter.HordeSupervisor,
             strategy: :one_for_one,
             members: :auto,
             distribution_strategy: AshPhoenixStarter.Cluster.RegionalDistribution
           ]},
          {Oban,
           AshOban.config(
             Application.fetch_env!(:ash_phoenix_starter, :ash_domains),
             Application.fetch_env!(:ash_phoenix_starter, Oban)
           )},
          AshPhoenixStarter.Accounts.PasswordResetScheduler,
          cache_child_spec(AppSettings, :app_settings_cache, :global_cache_config,
            gc_interval: :timer.seconds(120),
            max_size: 10_000
          ),
          cache_child_spec(TenantSettings, :tenant_settings_cache, :tenant_cache_config,
            gc_interval: :timer.seconds(60),
            max_size: 50_000
          ),
          AshPhoenixStarter.Payments.Registry,
          AshPhoenixStarter.Payments.ClusterSync,
          AshPhoenixStarter.Settings.CacheInvalidator,
          AshPhoenixStarterWeb.Presence,
          AshPhoenixStarterWeb.Endpoint,
          {AshAuthentication.Supervisor, [otp_app: :ash_phoenix_starter]}
        ]

    opts = [strategy: :one_for_one, name: AshPhoenixStarter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AshPhoenixStarterWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp timezone_cache_children do
    if Application.get_env(:ash_phoenix_starter, :timezone_cache_config) do
      [
        cache_child_spec(
          TimezoneResolution,
          :timezone_resolution_cache,
          :timezone_cache_config,
          gc_interval: :timer.hours(1),
          max_size: 5_000
        )
      ]
    else
      []
    end
  end

  defp cluster_children do
    case resolve_cluster_mode() do
      :horde ->
        [
          {Horde.Registry,
            [name: AshPhoenixStarter.HordeRegistry, keys: :unique, members: :auto]},
          {Horde.DynamicSupervisor,
            [name: AshPhoenixStarter.HordeSupervisor, strategy: :one_for_one, members: :auto]},
          {Horde.Registry,
            [name: AshPhoenixStarter.Bookings.HandlerRegistry, keys: :unique, members: :auto]},
          AshPhoenixStarter.Telemetry.HordeStarter,
          AshPhoenixStarter.ClusterTopologyObserver
        ]

      :standalone ->
        [
          AshPhoenixStarter.Telemetry.PgLeaderStarter
        ]
    end

  defp cache_child_spec(module, name, config_key, defaults) do
    env_cfg = Application.get_env(:ash_phoenix_starter, config_key, [])

    opts = [
      name: name,
      gc_interval: Keyword.get(env_cfg, :ttl_check_interval, defaults[:gc_interval]),
      max_size: Keyword.get(env_cfg, :max_size, defaults[:max_size])
    ]

    Supervisor.child_spec({module, opts}, id: name)
  end
end
