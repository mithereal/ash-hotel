defmodule AshPhoenixStarterWeb.Admin.CalendarLive do
  use AshPhoenixStarterWeb, :live_view
  use AshPhoenixStarterWeb.LiveTracking

  on_mount {AshPhoenixStarterWeb.LiveUserAuth, :live_user_required}

  import Ash.Query

  alias AshPhoenixStarter.Accounts.User
  alias AshPhoenixStarter.Accounts.UserProfile
  alias AshPhoenixStarter.Bookings.Booking
  alias AshPhoenixStarter.Bookings.Attendee
  alias AshPhoenixStarter.Bookings.Resource
  alias AshPhoenixStarter.Bookings.ValidationEngine
  alias AshPhoenixStarter.Bookings.ResourceRegistry

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    is_admin = AshPhoenixStarterWeb.Helpers.is_super_user?(current_user)

    if current_user && is_admin do
      organizations =
        AshPhoenixStarter.Accounts.Organization
        |> Ash.read!(actor: current_user)

      {:ok,
       socket
       |> assign(:current_date, Date.utc_today())
       |> assign(:organizations, organizations)
       |> assign(:selected_organization_id, nil)
       |> assign(:users, [])
       |> assign(:selected_user_id, nil)
       |> assign(:selected_tenant, nil)
       |> assign(:bookings, [])
       |> assign(:filtered_bookings, [])
       |> assign(:resources, [])
       |> assign(:events, [])
       |> assign(:show_modal?, false)
       |> assign(:editing_booking_id, nil)
       |> assign(
         :form,
         to_form(
           %{
             "start_time" => "",
             "end_time" => "",
             "notes" => "",
             "resource_id" => "",
             "attendees" => [
               %{
                 "attendee_id" => "",
                 "user_email" => "",
                 "guest_name" => "",
                 "guest_phone" => ""
               }
             ]
           },
           as: "booking"
         )
       )}
    else
      {:ok, push_navigate(socket, to: ~p"/sign-in")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    organization_identifier = params["organization_id"]
    user_id = params["user_id"]
    current_user = socket.assigns.current_user

    socket =
      if organization_identifier && organization_identifier != "" do
        organization =
          Enum.find(
            socket.assigns.organizations,
            &(&1.domain == organization_identifier or &1.id == organization_identifier)
          )

        if organization do
          tenant = organization.domain || organization.id

          users =
            User
            |> filter(current_organization == ^organization.domain)
            |> Ash.read!(actor: current_user, authorize?: false)

          bookings = fetch_organization_bookings(tenant, current_user)

          bookings =
            if user_id && user_id != "" do
              selected_user = Enum.find(users, &(&1.id == user_id))

              Enum.filter(bookings, fn b ->
                Enum.any?(b.attendees, fn att ->
                  to_string(att.user_id) == user_id or
                    (selected_user && att.email == to_string(selected_user.email))
                end)
              end)
            else
              bookings
            end

          filtered_bookings = filter_bookings_by_date(bookings, socket.assigns.current_date)
          events = map_user_bookings_to_events(bookings)

          socket
          |> assign(:selected_organization_id, organization_identifier)
          |> assign(:selected_tenant, tenant)
          |> assign(:users, users)
          |> assign(:selected_user_id, if(user_id == "", do: nil, else: user_id))
          |> assign(:bookings, bookings)
          |> assign(:filtered_bookings, filtered_bookings)
          |> assign(:events, events)
          |> assign(:resources, fetch_available_resources(tenant, current_user))
        else
          reset_selection(socket)
        end
      else
        reset_selection(socket)
      end

    {:noreply, socket}
  end

  defp reset_selection(socket) do
    socket
    |> assign(:selected_organization_id, nil)
    |> assign(:selected_tenant, nil)
    |> assign(:users, [])
    |> assign(:selected_user_id, nil)
    |> assign(:bookings, [])
    |> assign(:filtered_bookings, [])
    |> assign(:events, [])
    |> assign(:resources, [])
  end

  @impl true
  def handle_event("select_organization", %{"organization_id" => organization_id}, socket) do
    current_user = socket.assigns.current_user

    socket =
      if organization_id != "" do
        organization =
          Enum.find(
            socket.assigns.organizations,
            fn t -> to_string(t.domain) == organization_id end
          )

        if organization do
          tenant = organization.domain || to_string(organization.id)

          users =
            User
            |> filter(current_organization == ^organization.domain)
            |> Ash.read!(actor: current_user, authorize?: false)

          bookings = fetch_organization_bookings(tenant, current_user)
          filtered_bookings = filter_bookings_by_date(bookings, socket.assigns.current_date)
          events = map_user_bookings_to_events(bookings)

          socket
          |> assign(:selected_organization_id, organization_id)
          |> assign(:selected_tenant, tenant)
          |> assign(:users, users)
          |> assign(:selected_user_id, nil)
          |> assign(:bookings, bookings)
          |> assign(:filtered_bookings, filtered_bookings)
          |> assign(:events, events)
          |> assign(:resources, fetch_available_resources(tenant, current_user))
        else
          reset_selection(socket)
        end
      else
        reset_selection(socket)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_user", %{"user_id" => user_id}, socket) do
    tenant = socket.assigns.selected_tenant
    current_user = socket.assigns.current_user

    bookings =
      if tenant do
        base_bookings = fetch_organization_bookings(tenant, current_user)

        if user_id != "" do
          selected_user = Enum.find(socket.assigns.users, &(&1.id == user_id))

          Enum.filter(base_bookings, fn b ->
            Enum.any?(b.attendees, fn att ->
              to_string(att.user_id) == user_id or
                (selected_user && att.email == to_string(selected_user.email))
            end)
          end)
        else
          base_bookings
        end
      else
        []
      end

    filtered_bookings = filter_bookings_by_date(bookings, socket.assigns.current_date)
    events = map_user_bookings_to_events(bookings)

    {:noreply,
     socket
     |> assign(:selected_user_id, if(user_id == "", do: nil, else: user_id))
     |> assign(:bookings, bookings)
     |> assign(:filtered_bookings, filtered_bookings)
     |> assign(:events, events)}
  end

  @impl true
  def handle_event("open_booking_modal", _params, socket) do
    schedule_modal_tick()

    default_start = default_future_datetime_local(30)
    default_end = default_future_datetime_local(30 + 3600)

    {:noreply,
     socket
     |> assign(:show_modal?, true)
     |> assign(:editing_booking_id, nil)
     |> assign(:modal_rolling_time?, true)
     |> assign(
       :form,
       to_form(
         %{
           "start_time" => default_start,
           "end_time" => default_end,
           "notes" => "",
           "resource_id" => "",
           "attendees" => [
             %{
               "attendee_id" => "",
               "user_email" => "",
               "guest_name" => "",
               "guest_phone" => ""
             }
           ]
         },
         as: "booking"
       )
     )}
  end

  @impl true
  def handle_event("close_booking_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(show_modal?: false, editing_booking_id: nil, modal_rolling_time?: false)}
  end

  @impl true
  def handle_info(:modal_time_tick, socket) do
    socket =
      if socket.assigns[:show_modal?] && is_nil(socket.assigns[:editing_booking_id]) &&
           socket.assigns[:modal_rolling_time?] do
        schedule_modal_tick()

        default_start = default_future_datetime_local(30)
        default_end = default_future_datetime_local(30 + 3600)

        current_params = socket.assigns.form.params || %{}

        updated_params =
          current_params
          |> Map.put("start_time", default_start)
          |> Map.put("end_time", default_end)

        assign(socket, :form, to_form(updated_params, as: "booking"))
      else
        socket
      end

    {:noreply, socket}
  end

  defp schedule_modal_tick do
    Process.send_after(self(), :modal_time_tick, 10_000)
  end

  defp default_future_datetime_local(seconds_ahead, additional_duration_seconds \\ 0) do
    DateTime.utc_now()
    |> DateTime.shift_zone!("America/Phoenix")
    |> DateTime.add(seconds_ahead + additional_duration_seconds, :second)
    |> NaiveDateTime.to_string()
    |> String.slice(0, 16)
  end

  @impl true
  def handle_event("edit_booking", %{"id" => event_id}, socket) do
    open_edit_modal(event_id, socket)
  end

  @impl true
  def handle_event("delete_booking", %{"id" => booking_id}, socket) do
    tenant = socket.assigns.selected_tenant
    actor = socket.assigns.current_user

    case Ash.get(Booking, booking_id, actor: actor, tenant: tenant) do
      {:ok, booking} ->
        case Ash.destroy(booking, actor: actor, tenant: tenant, authorize?: false) do
          :ok ->
            reload_and_reply_success(socket, "Booking deleted successfully.")

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Failed to delete booking.")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not find booking to delete.")}
    end
  end

  @impl true
  def handle_event("add_attendee", _params, socket) do
    form_params = socket.assigns.form.params
    attendees_list = extract_attendees_list(Map.get(form_params, "attendees"))

    updated_attendees =
      attendees_list ++
        [
          %{
            "attendee_id" => "",
            "user_email" => "",
            "guest_name" => "",
            "guest_phone" => ""
          }
        ]

    updated_params = Map.put(form_params, "attendees", updated_attendees)
    {:noreply, assign(socket, :form, to_form(updated_params, as: "booking"))}
  end

  @impl true
  def handle_event("remove_attendee", %{"index" => index}, socket) do
    form_params = socket.assigns.form.params
    attendees_list = extract_attendees_list(Map.get(form_params, "attendees"))
    index = safe_to_int(index)

    updated_attendees =
      attendees_list
      |> Enum.with_index()
      |> Enum.reject(fn {_att, i} -> i == index end)
      |> Enum.map(fn {att, _i} -> att end)

    updated_attendees =
      if updated_attendees == [] do
        [%{"attendee_id" => "", "user_email" => "", "guest_name" => "", "guest_phone" => ""}]
      else
        updated_attendees
      end

    updated_params = Map.put(form_params, "attendees", updated_attendees)
    {:noreply, assign(socket, :form, to_form(updated_params, as: "booking"))}
  end

  defp safe_to_int(val) when is_integer(val), do: val

  defp safe_to_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp safe_to_int(_), do: 0

  @impl true
  def handle_event("validate_booking_form", %{"booking" => booking_params}, socket) do
    tenant = socket.assigns.selected_tenant
    actor = socket.assigns.current_user
    users = socket.assigns.users

    attendees_list = extract_attendees_list(booking_params["attendees"])

    updated_attendees =
      Enum.map(attendees_list, fn att_params ->
        enrich_attendee_params(att_params, users, actor, tenant)
      end)

    booking_params = Map.put(booking_params, "attendees", updated_attendees)
    {:noreply, assign(socket, :form, to_form(booking_params, as: "booking"))}
  end

  defp enrich_attendee_params(att_params, users, actor, tenant) do
    attendee_id = att_params["attendee_id"]

    if attendee_id && attendee_id != "" do
      user = Enum.find(users, &(&1.id == attendee_id))

      profile =
        UserProfile
        |> filter(user_id == ^attendee_id)
        |> Ash.read!(actor: actor, tenant: tenant)
        |> List.first()

      profile_name =
        if profile do
          "#{profile.first_name} #{profile.last_name}" |> String.trim()
        else
          nil
        end

      profile_phone = if profile, do: profile.mobile_number || profile.phone_number, else: nil
      user_email = if user, do: to_string(user.email), else: nil

      att_params
      |> Map.update("user_email", user_email, fn current ->
        if current == nil || current == "", do: user_email, else: current
      end)
      |> Map.update("guest_name", profile_name || user_email, fn current ->
        if current == nil || current == "", do: profile_name || user_email, else: current
      end)
      |> Map.update("guest_phone", profile_phone, fn current ->
        if current == nil || current == "", do: profile_phone, else: current
      end)
    else
      att_params
    end
  end

  @impl true
  def handle_event("create_booking", %{"booking" => booking_params}, socket) do
    tenant = socket.assigns.selected_tenant
    actor = socket.assigns.current_user
    resource_id = booking_params["resource_id"]
    attendees_list = extract_attendees_list(booking_params["attendees"])

    with {:ok, resource} <- fetch_resource(resource_id, actor, tenant) do
      timezone = Map.get(resource.metadata || %{}, "timezone", "America/Phoenix")

      start_time = parse_datetime(booking_params["start_time"], timezone)
      end_time = parse_datetime(booking_params["end_time"], timezone)
      handler = ResourceRegistry.handler_for(resource.type)

      with :ok <-
             ValidationEngine.validate_booking_slot(
               start_time,
               end_time,
               resource.type,
               resource_id,
               tenant: tenant,
               actor: actor
             ) do
        booking_attrs =
          booking_params
          |> Map.drop(["attendees"])
          |> Map.put("organizer_id", actor.id)
          |> Map.put("resource_id", resource_id)
          |> Map.put("start_time", start_time)
          |> Map.put("end_time", end_time)

        changeset =
          Booking
          |> Ash.Changeset.for_create(:create, booking_attrs, actor: actor, tenant: tenant)

        changeset =
          if function_exported?(handler, :validate_custom_rules, 2) do
            handler.validate_custom_rules(changeset, actor)
          else
            changeset
          end

        case Ash.create(changeset, tenant: tenant, authorize?: false) do
          {:ok, booking} ->
            if function_exported?(handler, :on_booked, 2) do
              handler.on_booked(booking, actor)
            end

            Enum.each(attendees_list, fn att ->
              save_attendee_record(
                booking.id,
                att["attendee_id"],
                att["guest_name"],
                att["user_email"],
                actor,
                tenant
              )
            end)

            reload_and_reply_success(socket, "Booking created successfully.")

          {:error, %Ash.Changeset{} = changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}

          {:error, %Ash.Error.Invalid{changeset: %Ash.Changeset{} = changeset}} ->
            {:noreply, assign(socket, :form, to_form(changeset))}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Failed to create booking.")}
        end
      else
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}
      end
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  @impl true
  def handle_event("update_booking", %{"booking" => booking_params}, socket) do
    tenant = socket.assigns.selected_tenant
    actor = socket.assigns.current_user
    resource_id = booking_params["resource_id"]
    booking_id = booking_params["id"]

    with {:ok, resource} <- fetch_resource(resource_id, actor, tenant) do
      timezone = Map.get(resource.metadata || %{}, "timezone", "America/Phoenix")

      start_time = parse_datetime(booking_params["start_time"], timezone)
      end_time = parse_datetime(booking_params["end_time"], timezone)

      with :ok <-
             ValidationEngine.validate_booking_slot(
               start_time,
               end_time,
               resource.type,
               resource_id,
               exclude_booking_id: booking_id,
               tenant: tenant,
               actor: actor
             ) do
        booking_attrs =
          booking_params
          |> Map.drop(["id", "attendees"])
          |> Map.put("start_time", start_time)
          |> Map.put("end_time", end_time)

        booking = Ash.get!(Booking, booking_id, actor: actor, tenant: tenant)

        changeset =
          booking
          |> Ash.Changeset.for_update(:update, booking_attrs, actor: actor, tenant: tenant)

        case Ash.update(changeset, tenant: tenant, authorize?: false) do
          {:ok, _updated_booking} ->
            reload_and_reply_success(socket, "Booking updated successfully.")

          {:error, %Ash.Changeset{} = changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}

          {:error, %Ash.Error.Invalid{changeset: %Ash.Changeset{} = changeset}} ->
            {:noreply, assign(socket, :form, to_form(changeset))}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Failed to update booking.")}
        end
      else
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}
      end
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  defp fetch_resource(resource_id, actor, tenant) do
    case Ash.get(Resource, resource_id, actor: actor, tenant: tenant) do
      {:ok, nil} -> {:error, "Selected resource could not be found."}
      {:ok, resource} -> {:ok, resource}
      {:error, _} -> {:error, "Failed to fetch resource configuration."}
    end
  end

  defp extract_attendees_list(nil), do: []
  defp extract_attendees_list(attendees) when is_list(attendees), do: attendees

  defp extract_attendees_list(attendees) when is_map(attendees) do
    attendees
    |> Enum.sort_by(fn {k, _} -> safe_to_int(k) end)
    |> Enum.map(fn {_, v} -> v end)
  end

  defp extract_attendees_list(_), do: []

  defp parse_datetime(nil, _timezone), do: nil
  defp parse_datetime("", _timezone), do: nil

  defp parse_datetime(val, timezone) when is_binary(val) do
    naive_val =
      case NaiveDateTime.from_iso8601(val <> ":00") do
        {:ok, ndt} ->
          ndt

        _ ->
          case NaiveDateTime.from_iso8601(val) do
            {:ok, ndt} -> ndt
            _ -> nil
          end
      end

    case naive_val do
      nil ->
        nil

      ndt ->
        tz = timezone || "America/Phoenix"

        case DateTime.from_naive(ndt, tz) do
          {:ok, dt} -> dt
          {:ambiguous, dt, _} -> dt
          {:gap, dt, _} -> dt
          _ -> nil
        end
    end
  end

  defp parse_datetime(val, _timezone), do: val

  defp save_attendee_record(_booking_id, nil, _, _, _, _), do: :ok
  defp save_attendee_record(_booking_id, "", _, _, _, _), do: :ok

  defp save_attendee_record(booking_id, attendee_id, guest_name, user_email, actor, tenant) do
    Attendee
    |> Ash.Changeset.for_create(
      :create,
      %{
        booking_id: booking_id,
        user_id: attendee_id,
        name: guest_name,
        email: user_email
      },
      actor: actor,
      tenant: tenant
    )
    |> Ash.create!(tenant: tenant, authorize?: false)
  end

  defp reload_and_reply_success(socket, flash_message) do
    tenant = socket.assigns.selected_tenant
    actor = socket.assigns.current_user
    user_id = socket.assigns.selected_user_id

    bookings =
      if tenant do
        base_bookings = fetch_organization_bookings(tenant, actor)

        if user_id && user_id != "" do
          selected_user = Enum.find(socket.assigns.users, &(&1.id == user_id))

          Enum.filter(base_bookings, fn b ->
            Enum.any?(b.attendees, fn att ->
              to_string(att.user_id) == user_id or
                (selected_user && att.email == to_string(selected_user.email))
            end)
          end)
        else
          base_bookings
        end
      else
        []
      end

    filtered_bookings = filter_bookings_by_date(bookings, socket.assigns.current_date)
    events = map_user_bookings_to_events(bookings)

    {:noreply,
     socket
     |> put_flash(:info, flash_message)
     |> assign(:show_modal?, false)
     |> assign(:editing_booking_id, nil)
     |> assign(:bookings, bookings)
     |> assign(:filtered_bookings, filtered_bookings)
     |> assign(:events, events)}
  end

  @impl true
  def handle_info({:date_selected, date}, socket) do
    tenant = socket.assigns.selected_tenant
    actor = socket.assigns.current_user
    user_id = socket.assigns.selected_user_id

    all_bookings =
      cond do
        user_id && tenant ->
          user = Enum.find(socket.assigns.users, &(&1.id == user_id))
          if user, do: fetch_user_bookings(user, tenant, actor), else: []

        tenant ->
          fetch_organization_bookings(tenant, actor)

        true ->
          []
      end

    filtered_bookings = filter_bookings_by_date(all_bookings, date)
    events = map_user_bookings_to_events(all_bookings)

    {:noreply,
     socket
     |> assign(:current_date, date)
     |> assign(:bookings, all_bookings)
     |> assign(:filtered_bookings, filtered_bookings)
     |> assign(:events, events)}
  end

  @impl true
  def handle_info({:event_clicked, event_id}, socket) do
    open_edit_modal(event_id, socket)
  end

  defp open_edit_modal(event_id, socket) do
    tenant = socket.assigns.selected_tenant
    actor = socket.assigns.current_user

    case Booking |> Ash.get(event_id, actor: actor, tenant: tenant, load: [:attendees]) do
      {:ok, booking} ->
        attendees_form_data =
          if Enum.empty?(booking.attendees) do
            [%{"attendee_id" => "", "user_email" => "", "guest_name" => "", "guest_phone" => ""}]
          else
            booking.attendees
            |> Enum.map(fn att ->
              %{
                "attendee_id" =>
                  to_string(Map.get(att, :user_id) || Map.get(att, "user_id") || ""),
                "user_email" => to_string(Map.get(att, :email) || Map.get(att, "email") || ""),
                "guest_name" => to_string(Map.get(att, :name) || Map.get(att, "name") || ""),
                "guest_phone" => to_string(Map.get(att, :phone) || Map.get(att, "phone") || "")
              }
            end)
          end

        now_future =
          DateTime.utc_now()
          |> DateTime.shift_zone!("America/Phoenix")
          |> DateTime.add(30, :second)

        end_dt =
          case DateTime.compare(booking.end_time, now_future) do
            result when result in [:lt, :eq] ->
              DateTime.add(now_future, 3600, :second)

            _ ->
              booking.end_time
          end

        end_time = format_datetime_local(end_dt)

        form_data = %{
          "start_time" => default_future_datetime_local(30),
          "end_time" => end_time,
          "notes" => booking.notes || "",
          "resource_id" => booking.resource_id || "",
          "attendees" => attendees_form_data
        }

        {:noreply,
         socket
         |> assign(:show_modal?, true)
         |> assign(:editing_booking_id, booking.id)
         |> assign(:form, to_form(form_data, as: "booking"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not load booking for editing.")}
    end
  end

  defp format_datetime_local(nil), do: ""

  defp format_datetime_local(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("America/Phoenix")
    |> NaiveDateTime.to_string()
    |> String.slice(0, 16)
  end

  defp format_datetime_local(%NaiveDateTime{} = ndt) do
    NaiveDateTime.to_string(ndt) |> String.slice(0, 16)
  end

  defp format_datetime_local(_), do: ""

  @impl true
  def handle_info({:event_dropped, event_id, new_start, new_end}, socket) do
    tenant = socket.assigns.selected_tenant
    actor = socket.assigns.current_user

    booking = Ash.get!(Booking, event_id, actor: actor, tenant: tenant, load: [:resource])
    resource = booking.resource || %{type: :appointment}

    with :ok <-
           ValidationEngine.validate_booking_slot(
             new_start,
             new_end,
             resource.type,
             booking.resource_id,
             tenant: tenant,
             actor: actor
           ) do
      result =
        booking
        |> Ash.Changeset.for_update(:update, %{start_time: new_start, end_time: new_end},
          actor: actor,
          tenant: tenant
        )
        |> Ash.update(tenant: tenant)

      case result do
        {:ok, _updated} ->
          bookings =
            if socket.assigns.selected_user_id do
              user = Enum.find(socket.assigns.users, &(&1.id == socket.assigns.selected_user_id))
              fetch_user_bookings(user, tenant, actor)
            else
              fetch_organization_bookings(tenant, actor)
            end

          filtered_bookings = filter_bookings_by_date(bookings, socket.assigns.current_date)
          events = map_user_bookings_to_events(bookings)

          {:noreply,
           assign(socket,
             bookings: bookings,
             filtered_bookings: filtered_bookings,
             events: events
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to reschedule booking.")}
      end
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  defp fetch_organization_bookings(tenant, actor) do
    Booking
    |> load([:attendees, :resource])
    |> sort(start_time: :asc)
    |> Ash.read!(actor: actor, tenant: tenant)
  end

  defp fetch_user_bookings(user, tenant, actor) do
    Booking
    |> load([:attendees, :resource])
    |> filter(attendees.user_id == ^user.id or attendees.email == ^user.email)
    |> sort(start_time: :asc)
    |> Ash.read!(actor: actor, tenant: tenant)
  end

  defp fetch_available_resources(tenant, actor) do
    Resource
    |> Ash.read!(actor: actor, tenant: tenant)
  end

  defp filter_bookings_by_date(bookings, date) do
    Enum.filter(bookings, fn booking ->
      booking_date = NaiveDateTime.to_date(booking.start_time)
      Date.compare(booking_date, date) == :eq
    end)
  end

  defp map_user_bookings_to_events(bookings) do
    Enum.map(bookings, fn booking ->
      PhoenixLiveCalendar.event(
        to_string(booking.id),
        booking.start_time,
        title: booking.notes || "Booked Slot",
        end: booking.end_time,
        color: "bg-indigo-500"
      )
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} uri={@uri}>
      <div class="mx-auto max-w-6xl px-4 py-8 text-zinc-100">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold tracking-tight text-zinc-100">Admin Calendar Overview</h1>
        </div>

        <div class="bg-zinc-900/40 p-6 rounded-2xl border border-zinc-800/80 shadow-lg backdrop-blur-sm mb-8 flex flex-col md:flex-row gap-4">
          <div class="flex-1">
            <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
              Select Organization
            </label>
            <form phx-change="select_organization" phx-submit="select_organization">
              <select
                name="organization_id"
                class="w-full rounded-xl bg-zinc-900 border-zinc-700 text-zinc-100 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              >
                <option value="">-- Choose Organization --</option>
                <%= for organization <- @organizations do %>
                  <% val = organization.domain || organization.id %>
                  <option value={val} selected={val == @selected_organization_id}>
                    {organization.name} ({val})
                  </option>
                <% end %>
              </select>
            </form>
          </div>

          <div class="flex-1">
            <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
              Select User
            </label>
            <form phx-change="select_user" phx-submit="select_user">
              <select
                name="user_id"
                class="w-full rounded-xl bg-zinc-900 border-zinc-700 text-zinc-100 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:opacity-50"
                disabled={is_nil(@selected_organization_id)}
              >
                <option value="">-- Choose User --</option>
                <%= for user <- @users do %>
                  <option value={user.id} selected={user.id == @selected_user_id}>
                    {user.email}
                  </option>
                <% end %>
              </select>
            </form>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div class="md:col-span-2 bg-zinc-900/40 p-6 rounded-2xl border border-zinc-800/80 shadow-lg backdrop-blur-sm">
            <.live_component
              module={PhoenixLiveCalendar.CalendarComponent}
              id={"admin-calendar-#{@selected_organization_id || "none"}"}
              events={@events}
              selected_date={@current_date}
              selected_date_class="ring-2 ring-indigo-500 bg-indigo-500/10 rounded-lg text-zinc-100 font-semibold"
              views={[:month, :week, :day, :agenda]}
              on_date_select={fn date -> send(self(), {:date_selected, date}) end}
              on_event_click={fn id -> send(self(), {:event_clicked, id}) end}
              on_event_drop={
                fn event_id, new_start, new_end ->
                  send(self(), {:event_dropped, event_id, new_start, new_end})
                end
              }
            />
          </div>

          <div class="bg-zinc-900/40 shadow-lg border border-zinc-800/80 flex flex-col rounded-2xl overflow-hidden backdrop-blur-sm">
            <div>
              <.button
                class="w-full text-center py-3 text-sm font-semibold bg-indigo-600 text-white shadow hover:bg-indigo-500 transition-colors disabled:opacity-50"
                phx-click="open_booking_modal"
                disabled={is_nil(@selected_tenant)}
              >
                + New Booking / Meeting
              </.button>
            </div>

            <div class="w-full p-4 flex-1">
              <h2 class="text-sm font-bold uppercase tracking-wider text-zinc-400 mb-4">
                Schedule for {Calendar.strftime(@current_date, "%b %d, %Y")} ({length(
                  @filtered_bookings
                )})
              </h2>

              <div class="space-y-4 max-h-[500px] overflow-y-auto">
                <%= if Enum.empty?(@filtered_bookings) do %>
                  <p class="text-sm text-zinc-500">No events found for this date.</p>
                <% else %>
                  <%= for booking <- @filtered_bookings do %>
                    <div
                      class="p-4 rounded-xl bg-zinc-900/60 border border-zinc-800 flex flex-col gap-1 cursor-pointer hover:border-indigo-500 transition-colors"
                      phx-click="edit_booking"
                      phx-value-id={booking.id}
                    >
                      <span class="text-xs font-medium uppercase tracking-wider text-indigo-400 bg-indigo-500/10 px-2 py-0.5 rounded w-max">
                        {booking.status}
                      </span>
                      <div class="text-sm font-semibold text-zinc-100 mt-1">
                        {Calendar.strftime(booking.start_time, "%I:%M %p")} - {Calendar.strftime(
                          booking.end_time,
                          "%I:%M %p"
                        )}
                      </div>
                      <div class="text-xs text-zinc-400">
                        {booking.notes || "Scheduled appointment or stay"}
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Booking Modal Dialog --%>
        <%= if @show_modal? do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
            <div class="bg-zinc-900 border border-zinc-800 w-full max-w-lg p-6 rounded-2xl shadow-2xl text-zinc-100 max-h-[90vh] overflow-y-auto">
              <div class="flex justify-between items-center mb-4">
                <h3 class="text-lg font-bold">
                  {if @editing_booking_id, do: "Edit Booking / Meeting", else: "New Booking / Meeting"}
                </h3>
                <.button
                  phx-click="close_booking_modal"
                  class="text-zinc-400 hover:text-zinc-100"
                >
                  ✕
                </.button>
              </div>

              <.form
                for={@form}
                phx-change="validate_booking_form"
                phx-submit={if @editing_booking_id, do: "update_booking", else: "create_booking"}
                class="space-y-4"
              >
                <%= if @editing_booking_id do %>
                  <input type="hidden" name="booking[id]" value={@editing_booking_id} />
                <% end %>

                <div class="border-b border-zinc-800 pb-4 space-y-4">
                  <div class="flex justify-between items-center">
                    <h4 class="text-xs font-bold uppercase tracking-wider text-zinc-400">
                      Attendees
                    </h4>
                    <.button
                      phx-click="add_attendee"
                      class="text-xs bg-zinc-800 hover:bg-zinc-700 text-indigo-400 px-2 py-1 rounded-lg"
                    >
                      + Add Attendee
                    </.button>
                  </div>

                  <%= for {attendee, index} <- Enum.with_index(@form[:attendees].value || []) do %>
                    <div class="bg-zinc-950 p-4 rounded-xl border border-zinc-800 space-y-3 relative">
                      <%= if length(@form[:attendees].value || []) > 1 do %>
                        <.button
                          phx-click="remove_attendee"
                          phx-value-index={index}
                          class="absolute top-2 right-2 text-zinc-500 hover:text-red-400 text-xs"
                        >
                          ✕ Remove
                        </.button>
                      <% end %>

                      <div>
                        <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
                          Attendee / User
                        </label>
                        <select
                          name={"booking[attendees][#{index}][attendee_id]"}
                          class="w-full rounded-xl bg-zinc-900 border-zinc-700 text-zinc-100 text-sm"
                        >
                          <option value="">-- None (Manual Guest Entry) --</option>
                          <%= for user <- @users do %>
                            <option value={user.id} selected={attendee["attendee_id"] == user.id}>
                              {user.email}
                            </option>
                          <% end %>
                        </select>
                      </div>

                      <div>
                        <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
                          User Email
                        </label>
                        <input
                          type="email"
                          name={"booking[attendees][#{index}][user_email]"}
                          value={attendee["user_email"]}
                          class="w-full rounded-xl bg-zinc-900 border-zinc-700 text-zinc-100 text-sm"
                          placeholder="guest@example.com"
                        />
                      </div>

                      <div>
                        <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
                          Guest Name
                        </label>
                        <input
                          type="text"
                          name={"booking[attendees][#{index}][guest_name]"}
                          value={attendee["guest_name"]}
                          class="w-full rounded-xl bg-zinc-900 border-zinc-700 text-zinc-100 text-sm"
                          placeholder="John Doe"
                        />
                      </div>

                      <div>
                        <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
                          Guest Phone
                        </label>
                        <input
                          type="text"
                          name={"booking[attendees][#{index}][guest_phone]"}
                          value={attendee["guest_phone"]}
                          class="w-full rounded-xl bg-zinc-900 border-zinc-700 text-zinc-100 text-sm"
                          placeholder="555-0199"
                        />
                      </div>
                    </div>
                  <% end %>
                </div>

                <div>
                  <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
                    Resource
                  </label>
                  <select
                    name="booking[resource_id]"
                    class="w-full rounded-xl bg-zinc-950 border-zinc-700 text-zinc-100 text-sm"
                    required
                  >
                    <option value="">-- Select Resource --</option>
                    <%= for resource <- @resources do %>
                      <option value={resource.id} selected={@form[:resource_id].value == resource.id}>
                        {resource.name} ({resource.type})
                      </option>
                    <% end %>
                  </select>
                </div>

                <div>
                  <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
                    Start Time
                  </label>
                  <input
                    type="datetime-local"
                    name="booking[start_time]"
                    value={@form[:start_time].value}
                    class="w-full rounded-xl bg-zinc-950 border-zinc-700 text-zinc-100 text-sm"
                    required
                  />
                </div>

                <div>
                  <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
                    End Time
                  </label>
                  <input
                    type="datetime-local"
                    name="booking[end_time]"
                    value={@form[:end_time].value}
                    class="w-full rounded-xl bg-zinc-950 border-zinc-700 text-zinc-100 text-sm"
                    required
                  />
                </div>

                <div>
                  <label class="block text-xs font-semibold text-zinc-400 uppercase mb-1">
                    Notes / Description
                  </label>
                  <textarea
                    name="booking[notes]"
                    class="w-full rounded-xl bg-zinc-950 border-zinc-700 text-zinc-100 text-sm"
                    rows="3"
                    placeholder="Meeting purpose..."
                  ><%= @form[:notes].value %></textarea>
                </div>

                <div class="flex justify-between items-center pt-2">
                  <div>
                    <%= if @editing_booking_id do %>
                      <.button
                        phx-click="delete_booking"
                        phx-value-id={@editing_booking_id}
                        data-confirm="Are you sure you want to delete this booking?"
                        class="px-4 py-2 rounded-xl bg-red-600/20 text-red-400 text-sm font-semibold hover:bg-red-600/30 transition-colors"
                      >
                        Delete Booking
                      </.button>
                    <% end %>
                  </div>

                  <div class="flex gap-3">
                    <.button
                      phx-click="close_booking_modal"
                      class="px-4 py-2 rounded-xl bg-zinc-800/80 text-zinc-300 text-sm font-semibold hover:bg-zinc-700"
                    >
                      Cancel
                    </.button>
                    <.button class="px-4 py-2 rounded-xl bg-indigo-600 text-white text-sm font-semibold hover:bg-indigo-500">
                      {if @editing_booking_id, do: "Update Booking", else: "Create Booking"}
                    </.button>
                  </div>
                </div>
              </.form>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
