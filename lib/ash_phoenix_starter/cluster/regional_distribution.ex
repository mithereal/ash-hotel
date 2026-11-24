defmodule AshPhoenixStarter.Cluster.RegionalDistribution do
  @moduledoc """
  Custom Horde distribution strategy that pins regional processes (like `UsageTracker`)
  to OCI VMs running in the matching `region_id`, falling back to any alive node
  if no regional node is currently available.
  """
  @behaviour Horde.DistributionStrategy

  @impl true
  def choose_node(identifier, members) do
    alive_members = Enum.filter(members, &(&1.status == :alive))
    target_region = extract_region(identifier)

    matching_members =
      case target_region do
        nil -> alive_members
        region -> Enum.filter(alive_members, &(node_region(&1.name) == region))
      end

    pool = if matching_members != [], do: matching_members, else: alive_members

    case pool do
      [] ->
        {:error, :no_alive_nodes}

      nodes ->
        # Deterministic hash ring selection within the matching regional pool
        index = :erlang.phash2(identifier, length(nodes))
        {:ok, Enum.at(nodes, index)}
    end
  end

  @impl true
  def has_quorum?(_members), do: true

  # Extracts `region_id` from `UsageTracker` child specs: `{UsageTracker, %{region_id: "eu-frankfurt-1", ...}}`
  defp extract_region(%{start: {_mod, :start_link, [%{region_id: region_id}]}})
       when is_binary(region_id) and region_id != "global" do
    normalize_region(region_id)
  end

  defp extract_region(_), do: nil

  # Matches Erlang node names formatted like :"app_eu_frankfurt_1@10.0.1.12"
  defp node_region({_, node_name}), do: node_region(node_name)

  defp node_region(node_name) when is_atom(node_name) do
    case node_name |> Atom.to_string() |> String.split("@") |> List.first() do
      "app_" <> region -> normalize_region(region)
      _ -> nil
    end
  end

  defp normalize_region(region) do
    region
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "_")
  end
end
