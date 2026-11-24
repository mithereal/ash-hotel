defmodule AshPhoenixStarterWeb.BookingsLive.Show do
  use AshPhoenixStarterWeb, :live_view

  alias AshPhoenixStarter.Bookings.{Attendee, Booking, PubSub, UpdateService}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user

    if connected?(socket), do: PubSub.subscribe(tenant)

    case Ash.get(Booking, id, tenant: tenant, actor: actor, load: [:resource, :attendees]) do
      {:ok, %Booking{} = booking} ->
        {:ok,
         socket
         |> assign(:booking, booking)
         |> assign(:reschedule_form, build_reschedule_form(booking))
         |> assign(
           :attendee_form,
           to_form(%{"name" => "", "email" => "", "phone" => ""}, as: :attendee)
         )
         |> assign(:error_message, nil)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Booking not found.")
         |> push_navigate(to: ~p"/bookings/new")}
    end
  end

  @impl true
  def handle_info({:booking_event, _event, booking_id}, socket) do
    if socket.assigns.booking.id == booking_id do
      tenant = socket.assigns.current_tenant
      actor = socket.assigns.current_user

      case Ash.get(Booking, booking_id,
             tenant: tenant,
             actor: actor,
             load: [:resource, :attendees]
           ) do
        {:ok, %Booking{} = reloaded} ->
          {:noreply,
           socket
           |> assign(:booking, reloaded)
           |> assign(:reschedule_form, build_reschedule_form(reloaded))}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reschedule", %{"booking" => params}, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user
    booking = socket.assigns.booking

    updates = %{
      "start_time" => to_utc_iso8601(params["start_time"]),
      "end_time" => to_utc_iso8601(params["end_time"]),
      "notes" => params["notes"]
    }

    case UpdateService.update_booking(booking, updates, tenant, actor) do
      {:ok, updated} ->
        reloaded = Ash.load!(updated, [:resource, :attendees], tenant: tenant, actor: actor)

        {:noreply,
         socket
         |> assign(:booking, reloaded)
         |> assign(:reschedule_form, build_reschedule_form(reloaded))
         |> assign(:error_message, nil)
         |> put_flash(:info, "Booking updated and attendees notified.")}

      {:error, msg} when is_binary(msg) ->
        {:noreply, assign(socket, :error_message, msg)}

      {:error, err} ->
        {:noreply, assign(socket, :error_message, Exception.message(err))}
    end
  end

  @impl true
  def handle_event("cancel_booking", _params, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user

    case UpdateService.cancel_booking(socket.assigns.booking, tenant, actor) do
      {:ok, cancelled} ->
        reloaded = Ash.load!(cancelled, [:resource, :attendees], tenant: tenant, actor: actor)

        {:noreply,
         socket
         |> assign(:booking, reloaded)
         |> put_flash(:info, "Booking cancelled and cancellation notices sent.")}

      {:error, err} ->
        {:noreply, assign(socket, :error_message, Exception.message(err))}
    end
  end

  @impl true
  def handle_event("add_attendee", %{"attendee" => params}, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user
    booking = socket.assigns.booking

    attrs = Map.put(params, "booking_id", booking.id)

    case Attendee
         |> Ash.Changeset.for_create(:create, attrs, tenant: tenant, actor: actor)
         |> Ash.create(tenant: tenant) do
      {:ok, _attendee} ->
        PubSub.broadcast(tenant, :attendees_updated, booking.id)
        reloaded = Ash.load!(booking, [:resource, :attendees], tenant: tenant, actor: actor)

        {:noreply,
         socket
         |> assign(:booking, reloaded)
         |> assign(
           :attendee_form,
           to_form(%{"name" => "", "email" => "", "phone" => ""}, as: :attendee)
         )
         |> put_flash(:info, "Attendee added.")}

      {:error, err} ->
        {:noreply, assign(socket, :error_message, Exception.message(err))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6 space-y-6">
      <div class="flex items-center justify-between border-b pb-4">
        <div>
          <h1 class="text-2xl font-bold">{@booking.resource.name}</h1>
          <span class="inline-block mt-1 px-2 py-0.5 text-xs rounded bg-gray-100 uppercase">
            Status: {@booking.status}
          </span>
        </div>

        <.button
          :if={@booking.status != :cancelled}
          phx-click="cancel_booking"
          data-confirm="Cancel this booking and notify all attendees?"
          class="px-3 py-2 bg-red-600 text-white text-sm rounded hover:bg-red-700"
        >
          Cancel Booking
        </.button>
      </div>

      <div :if={@error_message} class="p-4 rounded bg-red-50 text-red-700 border border-red-200">
        {@error_message}
      </div>

      <.form
        :if={@booking.status != :cancelled}
        for={@reschedule_form}
        phx-submit="reschedule"
        class="space-y-4"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium mb-1">Start Time (UTC)</label>
            <input
              type="datetime-local"
              name="booking[start_time]"
              value={@reschedule_form[:start_time].value}
              class="w-full rounded border-gray-300"
            />
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">End Time (UTC)</label>
            <input
              type="datetime-local"
              name="booking[end_time]"
              value={@reschedule_form[:end_time].value}
              class="w-full rounded border-gray-300"
            />
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium mb-1">Notes</label>
          <textarea name="booking[notes]" rows="2" class="w-full rounded border-gray-300"><%= @reschedule_form[:notes].value %></textarea>
        </div>

        <.button
          type="submit"
          class="px-4 py-2 bg-indigo-600 text-white text-sm rounded hover:bg-indigo-700"
        >
          Save Changes & Notify Attendees
        </.button>
      </.form>

      <div class="space-y-3 pt-4 border-t">
        <h2 class="text-lg font-semibold">Attendees ({length(@booking.attendees)})</h2>

        <div class="border rounded divide-y">
          <div :for={att <- @booking.attendees} class="p-3 text-sm flex justify-between">
            <span><strong>{att.name}</strong> — {att.email}</span>
            <span class="text-gray-500">{att.phone}</span>
          </div>
        </div>

        <.form
          :if={@booking.status != :cancelled}
          for={@attendee_form}
          phx-submit="add_attendee"
          class="flex gap-2 pt-2"
        >
          <input
            type="text"
            name="attendee[name]"
            placeholder="Name"
            required
            class="rounded border-gray-300 flex-1"
          />
          <input
            type="email"
            name="attendee[email]"
            placeholder="Email"
            required
            class="rounded border-gray-300 flex-1"
          />
          <input
            type="text"
            name="attendee[phone]"
            placeholder="Phone"
            class="rounded border-gray-300 w-32"
          />
          <.button class="px-3 py-2 bg-gray-800 text-white text-sm rounded">+ Add</.button>
        </.form>
      </div>
    </div>
    """
  end

  defp build_reschedule_form(booking) do
    to_form(
      %{
        "start_time" => Calendar.strftime(booking.start_time, "%Y-%m-%dT%H:%M"),
        "end_time" => Calendar.strftime(booking.end_time, "%Y-%m-%dT%H:%M"),
        "notes" => booking.notes || ""
      },
      as: :booking
    )
  end

  defp to_utc_iso8601(<<date::binary-size(10), "T", time::binary-size(5)>>),
    do: "#{date}T#{time}:00Z"

  defp to_utc_iso8601(other), do: other
end
