# lib/ash_phoenix_starter/bookings/validation_engine.ex
defmodule AshPhoenixStarter.Bookings.ValidationEngine do
  @moduledoc """
  Validation engine handling time slot bounds, chronology, overlap checks,
  and resource-type specific booking policies across hotel rooms, units,
  property viewings, vendor dispatches, amenities,  and general meetings.
  """

  alias AshPhoenixStarter.Bookings.Booking
  import Ash.Query

  @multi_day_exempt_types [:hotel_room]

  @daytime_inspection_types [
    :property_viewing,
    :tenant_onboarding,
    :move_out_inspection
  ]

  @business_meeting_types [
    :appointment,
    :property_manager_meeting,
    :owner_meeting,
    :contract_signing,
    :general_meeting
  ]

  @facility_access_types [
    :amenity_reservation
  ]

  @spec validate_booking_slot(
          DateTime.t() | String.t() | nil,
          DateTime.t() | String.t() | nil,
          atom(),
          Ecto.UUID.t(),
          keyword()
        ) :: :ok | {:error, String.t()}
  def validate_booking_slot(start_time, end_time, resource_type, resource_id, options \\ []) do
    tenant = Keyword.get(options, :tenant)
    actor = Keyword.get(options, :actor)
    config = Keyword.get(options, :config, %{})
    exclude_booking_id = Keyword.get(options, :exclude_booking_id)

    with {:ok, parsed_start} <- normalize_datetime(start_time, "Start time"),
         {:ok, parsed_end} <- normalize_datetime(end_time, "End time"),
         :ok <- check_chronology(parsed_start, parsed_end),
         :ok <- check_future_date(parsed_start),
         :ok <- check_type_specific_rules(parsed_start, parsed_end, resource_type),
         :ok <- check_tenant_policies(parsed_start, parsed_end, resource_type, config),
         :ok <-
           check_no_overlap(
             parsed_start,
             parsed_end,
             resource_id,
             exclude_booking_id,
             tenant,
             actor
           ) do
      :ok
    end
  end

  defp normalize_datetime(nil, label), do: {:error, "#{label} cannot be blank."}
  defp normalize_datetime("", label), do: {:error, "#{label} cannot be blank."}
  defp normalize_datetime(%DateTime{} = dt, _label), do: {:ok, dt}

  defp normalize_datetime(dt_string, label) when is_binary(dt_string) do
    case DateTime.from_iso8601(dt_string) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, "#{label} must be a valid ISO-8601 timestamp."}
    end
  end

  defp normalize_datetime(_, label), do: {:error, "#{label} has an invalid format."}

  defp check_chronology(start_time, end_time) do
    case DateTime.compare(start_time, end_time) do
      :lt -> :ok
      _ -> {:error, "End time must be strictly after the start time."}
    end
  end

  defp check_future_date(start_time) do
    # Allow a 5-minute grace window in the past for quick testing/submission latency
    buffered_now = DateTime.add(DateTime.utc_now(), -300, :second)

    case DateTime.compare(start_time, buffered_now) do
      result when result in [:gt, :eq] -> :ok
      _ -> {:error, "Booking must be scheduled for a future time."}
    end
  end

  defp check_no_overlap(start_time, end_time, resource_id, exclude_booking_id, tenant, actor) do
    query =
      Booking
      |> filter(resource_id == ^resource_id)
      |> filter(status != :cancelled)
      |> filter(start_time < ^end_time and end_time > ^start_time)

    query =
      if exclude_booking_id do
        filter(query, id != ^exclude_booking_id)
      else
        query
      end

    case Ash.read(query, tenant: tenant, actor: actor, authorize?: false) do
      {:ok, []} ->
        :ok

      {:ok, _conflicts} ->
        {:error, "This time slot conflicts with an existing booking for this resource."}

      {:error, _reason} ->
        {:error, "Unable to verify booking availability at this time."}
    end
  end

  defp check_type_specific_rules(_start_time, _end_time, type)
       when type in @multi_day_exempt_types do
    :ok
  end

  defp check_type_specific_rules(start_time, _end_time, type)
       when type in @daytime_inspection_types do
    if start_time.hour >= 8 and start_time.hour < 19 do
      :ok
    else
      {:error, "Viewings and unit inspections must be scheduled between 8:00 AM and 7:00 PM."}
    end
  end

  defp check_type_specific_rules(start_time, _end_time, type)
       when type in @business_meeting_types do
    if start_time.hour >= 7 and start_time.hour < 21 do
      :ok
    else
      {:error,
       "Meetings, hearings, and appointments must be scheduled between 7:00 AM and 9:00 PM."}
    end
  end

  defp check_type_specific_rules(start_time, _end_time, type)
       when type in @facility_access_types do
    if start_time.hour >= 6 and start_time.hour < 23 do
      :ok
    else
      {:error,
       "Vendor access and amenity reservations must be scheduled between 6:00 AM and 11:00 PM."}
    end
  end

  defp check_type_specific_rules(_start_time, _end_time, _other_type) do
    :ok
  end

  defp check_tenant_policies(_start_time, _end_time, type, _config)
       when type in @multi_day_exempt_types do
    :ok
  end

  defp check_tenant_policies(start_time, end_time, _resource_type, config) do
    max_hours = Map.get(config, :max_duration_hours) || Map.get(config, "max_duration_hours")

    if max_duration_exceeded?(start_time, end_time, max_hours) do
      {:error, "Booking exceeds the maximum allowed duration for this organization."}
    else
      :ok
    end
  end

  defp max_duration_exceeded?(_start_time, _end_time, nil), do: false

  defp max_duration_exceeded?(start_time, end_time, max_hours) do
    diff_seconds = DateTime.diff(end_time, start_time, :second)
    diff_seconds > max_hours * 3600
  end
end
