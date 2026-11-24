defmodule MeshGateway.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    cluster_nodes =
      case System.get_env("CLUSTER_NODES") do
        nil -> []
        val -> String.split(val, ",", trim: true) |> Enum.map(&(&1 |> String.trim() |> String.to_atom()))
      end

    topologies =
      if cluster_nodes != [] do
        [
          oci_mesh: [
            strategy: Cluster.Strategy.Epmd,
            config: [hosts: cluster_nodes]
          ]
        ]
      else
        []
      end

    gateway_port = String.to_integer(System.get_env("GATEWAY_PORT") || "80")

    children = [
      {Cluster.Supervisor, [topologies, [name: MeshGateway.ClusterSupervisor]]},
      {Router.Registry, name: Router.Registry},
      {Bandit, plug: Router.Router, port: gateway_port}
    ]

    opts = [strategy: :one_for_one, name: MeshGateway.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
