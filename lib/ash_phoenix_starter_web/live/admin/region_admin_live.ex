defmodule AshPhoenixStarterWeb.Admin.RegionAdminLive do
  use AshPhoenixStarterWeb, :live_view

  alias AshPhoenixStarter.Billing.UsageTracker

  # OCI gives 10 TB/month of free outbound egress across regions
  @oci_free_egress_bytes 10 * 1024 * 1024 * 1024 * 1024
  @refresh_interval :timer.seconds(5)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_stats, @refresh_interval)
    end

    {:ok, assign_stats(socket)}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    Process.send_after(self(), :refresh_stats, @refresh_interval)
    {:noreply, assign_stats(socket)}
  end

  @impl true
  def handle_event("refresh_now", _params, socket) do
    {:noreply, assign_stats(socket)}
  end

  defp assign_stats(socket) do
    tenants = UsageTracker.cluster_stats()
    connected_nodes = [node() | Node.list()]

    total_bandwidth = Enum.reduce(tenants, 0, &(&1.bandwidth_used + &2))
    total_storage = Enum.reduce(tenants, 0, &(&1.storage_used + &2))

    regions =
      tenants
      |> Enum.group_by(& &1.region_id)
      |> Enum.map(fn {region_id, region_tenants} ->
        %{
          region_id: region_id,
          hotel_count: length(region_tenants),
          bandwidth_used: Enum.reduce(region_tenants, 0, &(&1.bandwidth_used + &2)),
          storage_used: Enum.reduce(region_tenants, 0, &(&1.storage_used + &2)),
          nodes: region_tenants |> Enum.map(& &1.node) |> Enum.uniq()
        }
      end)
      |> Enum.sort_by(& &1.bandwidth_used, :desc)

    socket
    |> assign(:connected_nodes, connected_nodes)
    |> assign(:regions, regions)
    |> assign(:tenants, Enum.sort_by(tenants, & &1.bandwidth_used, :desc))
    |> assign(:total_bandwidth, total_bandwidth)
    |> assign(:total_storage, total_storage)
    |> assign(:oci_free_limit, @oci_free_egress_bytes)
    |> assign(:oci_percent, Float.round(total_bandwidth / @oci_free_egress_bytes * 100, 2))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto p-6 space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">OCI Cluster &amp; Regional Usage</h1>

          <p class="text-sm text-gray-500">
            Connected Nodes ({length(@connected_nodes)}):
            <span class="font-mono text-xs">{Enum.join(@connected_nodes, ", ")}</span>
          </p>
        </div>

        <button
          type="button"
          phx-click="refresh_now"
          class="px-3 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded hover:bg-indigo-700"
        >
          Refresh Now
        </button>
      </div>
      <%!-- Top Summary Cards --%>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="p-4 bg-white border rounded-lg">
          <p class="text-xs text-gray-500 uppercase font-semibold">Total Cluster Egress</p>

          <p class="text-2xl font-bold mt-1">{format_bytes(@total_bandwidth)}</p>

          <p class="text-xs text-gray-500 mt-1">{@oci_percent}% of OCI 10 TB Free Tier</p>
        </div>

        <div class="p-4 bg-white border rounded-lg">
          <p class="text-xs text-gray-500 uppercase font-semibold">Total Object Storage</p>

          <p class="text-2xl font-bold mt-1">{format_bytes(@total_storage)}</p>

          <p class="text-xs text-gray-500 mt-1">Across {length(@tenants)} Active Properties</p>
        </div>

        <div class="p-4 bg-white border rounded-lg">
          <p class="text-xs text-gray-500 uppercase font-semibold">Active Regions</p>

          <p class="text-2xl font-bold mt-1">{length(@regions)}</p>

          <p class="text-xs text-gray-500 mt-1">Live via Horde &amp; libcluster</p>
        </div>
      </div>
      <%!-- Regional Breakdown --%>
      <div class="bg-white border rounded-lg overflow-hidden">
        <div class="px-4 py-3 border-b bg-gray-50">
          <h2 class="text-sm font-semibold">Traffic by Geographic Region</h2>
        </div>

        <table class="min-w-full divide-y divide-gray-200 text-sm">
          <thead class="bg-gray-50 text-left text-xs text-gray-500 uppercase">
            <tr>
              <th class="px-4 py-2">Region ID</th>

              <th class="px-4 py-2">Hotels</th>

              <th class="px-4 py-2">Bandwidth Used</th>

              <th class="px-4 py-2">Storage Used</th>

              <th class="px-4 py-2">Host OCI Node(s)</th>
            </tr>
          </thead>

          <tbody class="divide-y divide-gray-100">
            <%= for region <- @regions do %>
              <tr>
                <td class="px-4 py-2 font-medium">{region.region_id}</td>

                <td class="px-4 py-2">{region.hotel_count}</td>

                <td class="px-4 py-2">{format_bytes(region.bandwidth_used)}</td>

                <td class="px-4 py-2">{format_bytes(region.storage_used)}</td>

                <td class="px-4 py-2 font-mono text-xs">{Enum.join(region.nodes, ", ")}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
      <%!-- Per-Hotel Breakdown --%>
      <div class="bg-white border rounded-lg overflow-hidden">
        <div class="px-4 py-3 border-b bg-gray-50">
          <h2 class="text-sm font-semibold">Per-Hotel Quota Status</h2>
        </div>

        <table class="min-w-full divide-y divide-gray-200 text-sm">
          <thead class="bg-gray-50 text-left text-xs text-gray-500 uppercase">
            <tr>
              <th class="px-4 py-2">Hotel (Org ID)</th>

              <th class="px-4 py-2">Region</th>

              <th class="px-4 py-2">Bandwidth / Limit</th>

              <th class="px-4 py-2">Storage / Limit</th>

              <th class="px-4 py-2">Status</th>
            </tr>
          </thead>

          <tbody class="divide-y divide-gray-100">
            <%= for t <- @tenants do %>
              <tr>
                <td class="px-4 py-2 font-mono text-xs">{t.org_id}</td>

                <td class="px-4 py-2">{t.region_id}</td>

                <td class="px-4 py-2">
                  {format_bytes(t.bandwidth_used)} / {format_bytes(t.bandwidth_limit)}
                </td>

                <td class="px-4 py-2">
                  {format_bytes(t.storage_used)} / {format_bytes(t.storage_limit)}
                </td>

                <td class="px-4 py-2">
                  <span class={[
                    "px-2 py-0.5 rounded-full text-xs font-medium",
                    status_badge_class(t.alert_level)
                  ]}>
                    {t.alert_level}
                  </span>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp status_badge_class(:capped_100), do: "bg-red-100 text-red-800"
  defp status_badge_class(:warn_80), do: "bg-amber-100 text-amber-800"
  defp status_badge_class(_), do: "bg-emerald-100 text-emerald-800"

  defp format_bytes(bytes) when bytes >= 1_099_511_627_776,
    do: "#{Float.round(bytes / 1_099_511_627_776, 2)} TB"

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 2)} MB"

  defp format_bytes(bytes) when bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes), do: "#{bytes} B"
end
