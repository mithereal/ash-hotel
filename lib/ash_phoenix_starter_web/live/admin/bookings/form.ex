# lib/ash_phoenix_starter_web/live/bookings_live/form.ex
defmodule AshPhoenixStarterWeb.BookingsLive.Form do
  use AshPhoenixStarterWeb, :live_view

  import Ash.Query

  alias AshPhoenixStarter.Bookings.{
    Attendee,
    Booking,
    BookingHandler,
    CreationService,
    Resource,
    PubSub
  }

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user

    resources =
      Resource
      |> filter(active == true)
      |> Ash.read!(tenant: tenant, actor: actor)

    booking_form =
      to_form(
        %{
          "resource_id" => List.first(resources) && List.first(resources).id,
          "start_time" => "",
          "end_time" => "",
          "notes" => ""
        },
        as: :booking
      )

    {:ok,
     socket
     |> assign(:step, :booking_details)
     |> assign(:resources, resources)
     |> assign(:booking_form, booking_form)
     |> assign(:booking, nil)
     |> assign(:attendees, [])
     |> assign(:attendee_form, blank_attendee_form())
     |> assign(:error_message, nil)}
  end

  # --- Step 1: Create Booking Slot ---

  @impl true
  def handle_event("validate_booking", %{"booking" => params}, socket) do
    {:noreply, assign(socket, :booking_form, to_form(params, as: :booking))}
  end

  @impl true
  def handle_event("save_booking", %{"booking" => params}, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user
    resource_id = params["resource_id"]

    booking_payload = %{
      "start_time" => to_utc_iso8601(params["start_time"]),
      "end_time" => to_utc_iso8601(params["end_time"]),
      "notes" => params["notes"],
      "organizer_id" => actor && actor.id
    }

    case CreationService.create_booking(booking_payload, resource_id, tenant, actor,
           notify?: false
         ) do
      {:ok, %Booking{} = booking} ->
        {:noreply,
         socket
         |> assign(:booking, booking)
         |> assign(:step, :attendees)
         |> assign(:error_message, nil)
         |> put_flash(:info, "Time slot reserved! Now add attendees below.")}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, :error_message, message)}

      {:error, error} ->
        {:noreply, assign(socket, :error_message, Exception.message(error))}
    end
  end

  # --- Step 2: Add / Remove Attendees & Finalize ---

  @impl true
  def handle_event("add_attendee", %{"attendee" => params}, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user
    booking = socket.assigns.booking

    attrs =
      params
      |> Map.put("booking_id", booking.id)

    case Attendee
         |> Ash.Changeset.for_create(:create, attrs, tenant: tenant, actor: actor)
         |> Ash.create(tenant: tenant) do
      {:ok, attendee} ->
        {:noreply,
         socket
         |> update(:attendees, fn list -> list ++ [attendee] end)
         |> assign(:attendee_form, blank_attendee_form())
         |> assign(:error_message, nil)}

      {:error, error} ->
        {:noreply, assign(socket, :error_message, Exception.message(error))}
    end
  end

  @impl true
  def handle_event("remove_attendee", %{"id" => attendee_id}, socket) do
    tenant = socket.assigns.current_tenant
    actor = socket.assigns.current_user

    with {:ok, attendee} <- Ash.get(Attendee, attendee_id, tenant: tenant, actor: actor),
         :ok <- Ash.destroy(attendee, tenant: tenant, actor: actor) do
      {:noreply,
       update(socket, :attendees, fn list ->
         Enum.reject(list, &(&1.id == attendee_id))
       end)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not remove attendee.")}
    end
  end

  @impl true
  def handle_event("finalize_booking", _params, socket) do
    booking = socket.assigns.booking
    tenant = socket.assigns.current_tenant

    BookingHandler.notify_attendees(booking, :booked)
    PubSub.broadcast(tenant, :attendees_updated, booking.id)

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Booking finalized and invites queued for #{length(socket.assigns.attendees)} attendee(s)."
     )
     |> push_navigate(to: ~p"/bookings/#{booking.id}")}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6 space-y-6">
      <div class="flex items-center justify-between border-b pb-4">
        <h1 class="text-2xl font-bold">
          {if @step == :booking_details,
            do: "Step 1: Reserve Time Slot",
            else: "Step 2: Add Attendees"}
        </h1>
        <span class="text-sm text-gray-500">
          {if @step == :booking_details, do: "1 of 2", else: "2 of 2"}
        </span>
      </div>

      <div :if={@error_message} class="p-4 rounded bg-red-50 text-red-700 border border-red-200">
        {@error_message}
      </div>

      <%!-- STEP 1: BOOKING DETAILS FORM --%>
      <.form
        :if={@step == :booking_details}
        for={@booking_form}
        phx-change="validate_booking"
        phx-submit="save_booking"
        class="space-y-4"
      >
        <div>
          <label class="block text-sm font-medium mb-1">Resource</label>
          <select name="booking[resource_id]" class="w-full rounded border-gray-300">
            <option
              :for={res <- @resources}
              value={res.id}
              selected={@booking_form[:resource_id].value == res.id}
            >
              {res.name} ({res.type})
            </option>
          </select>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium mb-1">Start Time (UTC)</label>
            <input
              type="datetime-local"
              name="booking[start_time]"
              value={@booking_form[:start_time].value}
              required
              class="w-full rounded border-gray-300"
            />
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">End Time (UTC)</label>
            <input
              type="datetime-local"
              name="booking[end_time]"
              value={@booking_form[:end_time].value}
              required
              class="w-full rounded border-gray-300"
            />
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium mb-1">Notes</label>
          <textarea
            name="booking[notes]"
            rows="3"
            class="w-full rounded border-gray-300"
          ><%= @booking_form[:notes].value %></textarea>
        </div>

        <div class="pt-2">
          <.button class="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700">
            Reserve Slot & Continue to Attendees →
          </.button>
        </div>
      </.form>

      <%!-- STEP 2: ATTENDEE MANAGER --%>
      <div :if={@step == :attendees} class="space-y-6">
        <div class="p-4 bg-gray-50 rounded border text-sm text-gray-700">
          <strong>Reserved Slot:</strong>
          {Calendar.strftime(@booking.start_time, "%b %d, %Y %H:%M")} – {Calendar.strftime(
            @booking.end_time,
            "%H:%M UTC"
          )}
        </div>

        <.form
          for={@attendee_form}
          phx-submit="add_attendee"
          class="grid grid-cols-1 md:grid-cols-3 gap-3 items-end"
        >
          <div>
            <label class="block text-xs font-medium mb-1">Name</label>
            <input
              type="text"
              name="attendee[name]"
              value={@attendee_form[:name].value}
              placeholder="Jane Doe"
              required
              class="w-full rounded border-gray-300"
            />
          </div>

          <div>
            <label class="block text-xs font-medium mb-1">Email</label>
            <input
              type="email"
              name="attendee[email]"
              value={@attendee_form[:email].value}
              placeholder="jane@example.com"
              required
              class="w-full rounded border-gray-300"
            />
          </div>

          <div class="flex gap-2">
            <div class="flex-1">
              <label class="block text-xs font-medium mb-1">Phone</label>
              <input
                type="text"
                name="attendee[phone]"
                value={@attendee_form[:phone].value}
                placeholder="555-0100"
                class="w-full rounded border-gray-300"
              />
            </div>
            <.button class="px-3 py-2 bg-gray-800 text-white rounded hover:bg-gray-900">
              + Add
            </.button>
          </div>
        </.form>

        <div class="border rounded divide-y">
          <div :if={Enum.empty?(@attendees)} class="p-4 text-sm text-gray-500 text-center">
            No attendees added yet. Add attendees above or finalize without guests.
          </div>

          <div :for={att <- @attendees} class="p-3 flex items-center justify-between text-sm">
            <div>
              <span class="font-medium">{att.name}</span>
              <span class="text-gray-500 ml-2">{att.email}</span>
              <span :if={att.phone} class="text-gray-400 ml-2">({att.phone})</span>
            </div>
            <.button
              phx-click="remove_attendee"
              phx-value-id={att.id}
              class="text-red-600 hover:underline text-xs"
            >
              Remove
            </.button>
          </div>
        </div>

        <div class="flex justify-end pt-4 border-t">
          <.button
            phx-click="finalize_booking"
            class="px-5 py-2 bg-green-600 text-white font-medium rounded hover:bg-green-700"
          >
            Finalize Booking & Send Invites
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp blank_attendee_form do
    to_form(%{"name" => "", "email" => "", "phone" => ""}, as: :attendee)
  end

  defp to_utc_iso8601(<<date::binary-size(10), "T", time::binary-size(5)>>) do
    "#{date}T#{time}:00Z"
  end

  defp to_utc_iso8601(other), do: other
end
