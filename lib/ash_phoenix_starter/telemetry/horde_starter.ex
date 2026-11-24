defmodule AshPhoenixStarter.Telemetry.HordeStarter do
  @moduledoc """
  Starts the ControlPlaneClient as a singleton under Horde (CLUSTER_MODE=horde).
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {AshPhoenixStarter.Telemetry.ControlPlaneClient,
       name:
         {:via, Horde.Registry,
          {AshPhoenixStarter.HordeRegistry, AshPhoenixStarter.Telemetry.ControlPlaneClient}}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
