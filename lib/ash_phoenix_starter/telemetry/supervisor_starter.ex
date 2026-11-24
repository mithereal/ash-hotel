defmodule AshPhoenixStarter.Telemetry.SupervisorStarter do
  @moduledoc """
  Ensures the singleton `ControlPlaneClient` is started inside `Horde.DynamicSupervisor`.
  Safe to run on every node in the tenant's cluster; Horde ignores duplicate starts.
  """
  use Task, restart: :transient

  alias AshPhoenixStarter.Telemetry.ControlPlaneClient

  def start_link(_opts) do
    Task.start_link(__MODULE__, :ensure_started, [])
  end

  def ensure_started do
    if Application.get_env(:AshPhoenixStarter, :control_plane_ws_url) do
      child_spec = %{
        id: ControlPlaneClient,
        start: {ControlPlaneClient, :start_link, [[]]},
        restart: :permanent
      }

      case Horde.DynamicSupervisor.start_child(AshPhoenixStarter.HordeSupervisor, child_spec) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end
end
