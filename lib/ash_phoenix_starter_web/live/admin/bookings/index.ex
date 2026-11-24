defmodule AshPhoenixStarterWeb.BookingsLive.Index do
  use AshPhoenixStarterWeb, :live_view

  import Ash.Query
  alias AshPhoenixStarter.Bookings.{Booking, PubSub, Resource, UpdateService}

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user

    if connected?(socket), do: PubSub.subscribe(tenant)

    resources =
      Resource
      |> sort(name: :asc)
      |> Ash.read!(tenant: tenant, actor: actor)

    {:ok,
     socket
     |> assign(:resources, resources)
     |> assign(:selected_resource_id, "all")
     |> assign(:selected_status, "upcoming")
     |> load_bookings()}
  end

  @impl true
  def handle_info({:booking_event, _event, _booking_id}, socket) do
    {:noreply, load_bookings(socket)}
  end

  @impl true
  def handle_event("filter", %{"resource_id" => resource_id, "status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:selected_resource_id, resource_id)
     |> assign(:selected_status, status)
     |> load_bookings()}
  end

  @impl true
  def handle_event("cancel_booking", %{"id" => booking_id}, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user

    case UpdateService.cancel_booking(booking_id, tenant, actor) do
      {:ok, _cancelled} ->
        {:noreply,
         socket
         |> put_flash(:info, "Booking cancelled and attendees notified.")
         |> load_bookings()}

      {:error, _err} ->
        {:noreply, put_flash(socket, :error, "Unable to cancel booking.")}
    end
  end

  defp load_bookings(socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user
    resource_id = socket.assigns.selected_resource_id
    status_filter = socket.assigns.selected_status
    now = DateTime.utc_now()

    query =
      Booking
      |> load([:resource, :attendees, :organizer])
      |> sort(start_time: :asc)

    query =
      if resource_id != "all" and resource_id != "" do
        filter(query, resource_id == ^resource_id)
      else
        query
      end

    query =
      case status_filter do
        "upcoming" ->
          filter(query, status != :cancelled and end_time >= ^now)

        "cancelled" ->
          filter(query, status == :cancelled)

        _ ->
          query
      end

    bookings = Ash.read!(query, tenant: tenant, actor: actor)
    assign(socket, :bookings, bookings)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto p-6 space-y-6">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 border-b pb-4">
        <div>
          <h1 class="text-2xl font-bold">Bookings & Reservations</h1>
          <p class="text-sm text-gray-500">Manage scheduled resources, meetings, and attendees.</p>
        </div>

        <.link
          navigate={~p"/bookings/new"}
          class="inline-flex items-center justify-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded hover:bg-indigo-700"
        >
          + New Booking
        </.link>
      </div>

      <%!-- Filter Bar --%>
      <form
        phx-change="filter"
        class="flex flex-wrap items-center gap-4 bg-gray-50 p-4 rounded border"
      >
        <div>
          <label class="block text-xs font-medium text-gray-600 mb-1">Resource</label>
          <select name="resource_id" class="rounded border-gray-300 text-sm">
            <option value="all" selected={@selected_resource_id == "all"}>All Resources</option>
            <option
              :for={res <- @resources}
              value={res.id}
              selected={@selected_resource_id == res.id}
            >
              {res.name}
            </option>
          </select>
        </div>

        <div>
          <label class="block text-xs font-medium text-gray-600 mb-1">View</label>
          <select name="status" class="rounded border-gray-300 text-sm">
            <option value="upcoming" selected={@selected_status == "upcoming"}>
              Upcoming Active
            </option>
            <option value="all" selected={@selected_status == "all"}>All Bookings</option>
            <option value="cancelled" selected={@selected_status == "cancelled"}>Cancelled</option>
          </select>
        </div>
      </form>

      <%!-- Bookings Table --%>
      <div class="border rounded overflow-hidden">
        <div :if={Enum.empty?(@bookings)} class="p-8 text-center text-sm text-gray-500">
          No bookings match the selected filters.
        </div>

        <table :if={not Enum.empty?(@bookings)} class="min-w-full divide-y divide-gray-200 text-sm">
          <thead class="bg-gray-50 text-left text-xs font-medium text-gray-500 uppercase">
            <tr>
              <th class="px-4 py-3">Resource</th>
              <th class="px-4 py-3">Schedule (UTC)</th>
              <th class="px-4 py-3">Attendees</th>
              <th class="px-4 py-3">Status</th>
              <th class="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white">
            <tr :for={booking <- @bookings} class="hover:bg-gray-50">
              <td class="px-4 py-3">
                <div class="font-medium text-gray-900">
                  {(booking.resource && booking.resource.name) || "Unknown Resource"}
                </div>
                <div :if={booking.resource} class="text-xs text-gray-500">
                  {booking.resource.type}
                </div>
              </td>

              <td class="px-4 py-3 text-gray-700">
                <div>{Calendar.strftime(booking.start_time, "%b %d, %Y %H:%M")}</div>
                <div class="text-xs text-gray-500">
                  to {Calendar.strftime(booking.end_time, "%b %d, %Y %H:%M")}
                </div>
              </td>

              <td class="px-4 py-3 text-gray-700">
                {length(booking.attendees)} guest(s)
              </td>

              <td class="px-4 py-3">
                <span class={[
                  "px-2 py-0.5 text-xs rounded font-medium uppercase",
                  booking.status == :cancelled && "bg-red-100 text-red-700",
                  booking.status == :confirmed && "bg-green-100 text-green-700",
                  booking.status == :scheduled && "bg-blue-100 text-blue-700"
                ]}>
                  {booking.status}
                </span>
              </td>

              <td class="px-4 py-3 text-right space-x-3">
                <.link
                  navigate={~p"/bookings/#{booking.id}"}
                  class="text-indigo-600 hover:underline font-medium"
                >
                  Manage
                </.link>

                <.button
                  :if={booking.status != :cancelled}
                  phx-click="cancel_booking"
                  phx-value-id={booking.id}
                  data-confirm="Cancel this booking and notify attendees?"
                  class="text-red-600 hover:underline"
                >
                  Cancel
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
