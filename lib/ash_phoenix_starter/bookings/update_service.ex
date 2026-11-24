# lib/ash_phoenix_starter/bookings/update_service.ex
defmodule AshPhoenixStarter.Bookings.UpdateService do
  @moduledoc """
  Handles updating and rescheduling existing bookings while enforcing
  organization duration policies, overlap checks (excluding the current booking),
  resource-type custom validation rules, and post-update/cancellation callbacks.
  """

  alias AshPhoenixStarter.Bookings.{Booking, PubSub, Resource, ResourceRegistry, ValidationEngine}
  alias AshPhoenixStarter.Settings.Manager

  def update_booking(%Booking{} = booking, update_params, tenant, actor) do
    target_resource_id = fetch_param(update_params, :resource_id, booking.resource_id)
    new_start_time = fetch_param(update_params, :start_time, booking.start_time)
    new_end_time = fetch_param(update_params, :end_time, booking.end_time)
    new_status = fetch_param(update_params, :status, booking.status)

    with {:ok, resource} <- Ash.get(Resource, target_resource_id, tenant: tenant, actor: actor),
         :ok <- ensure_active_when_not_cancelling(resource, new_status),
         :ok <-
           maybe_validate_slot(
             booking,
             resource,
             new_start_time,
             new_end_time,
             new_status,
             tenant,
             actor
           ) do
      handler = ResourceRegistry.handler_for(resource.type)

      changeset =
        booking
        |> Ash.Changeset.for_update(:update, update_params, actor: actor, tenant: tenant)
        |> handler.validate_custom_rules(actor)

      case Ash.update(changeset, tenant: tenant, authorize?: false) do
        {:ok, updated_booking} ->
          dispatch_lifecycle_callback(handler, booking, updated_booking, actor)

          event = if updated_booking.status == :cancelled, do: :cancelled, else: :updated
          PubSub.broadcast(tenant, event, updated_booking.id)

          {:ok, updated_booking}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def update_booking(booking_id, update_params, tenant, actor) when is_binary(booking_id) do
    with {:ok, booking} <- Ash.get(Booking, booking_id, tenant: tenant, actor: actor) do
      update_booking(booking, update_params, tenant, actor)
    end
  end

  def cancel_booking(booking_or_id, tenant, actor) do
    update_booking(booking_or_id, %{status: :cancelled}, tenant, actor)
  end

  # --- Private Helpers ---

  defp dispatch_lifecycle_callback(handler, previous_booking, updated_booking, actor) do
    just_cancelled? =
      previous_booking.status != :cancelled and updated_booking.status == :cancelled

    if just_cancelled? do
      if function_exported?(handler, :on_cancelled, 2) do
        handler.on_cancelled(updated_booking, actor)
      end
    else
      if function_exported?(handler, :on_updated, 2) do
        handler.on_updated(updated_booking, actor)
      end
    end
  end

  defp ensure_active_when_not_cancelling(_resource, status)
       when status in [:cancelled, "cancelled"],
       do: :ok

  defp ensure_active_when_not_cancelling(%{active: true}, _status), do: :ok

  defp ensure_active_when_not_cancelling(_, _status),
    do: {:error, "This booking resource is currently inactive."}

  defp maybe_validate_slot(booking, resource, new_start, new_end, new_status, tenant, actor) do
    cancelling? = new_status in [:cancelled, "cancelled"]
    reopening? = booking.status == :cancelled and not cancelling?
    slot_changed? = slot_modified?(booking, resource.id, new_start, new_end)

    if not cancelling? and (slot_changed? or reopening?) do
      max_hours = Manager.get_tenant(tenant, :max_booking_duration_hours)

      ValidationEngine.validate_booking_slot(
        new_start,
        new_end,
        resource.type,
        resource.id,
        tenant: tenant,
        actor: actor,
        exclude_booking_id: booking.id,
        config: %{max_duration_hours: max_hours}
      )
    else
      :ok
    end
  end

  defp slot_modified?(booking, target_resource_id, new_start, new_end) do
    booking.resource_id != target_resource_id or
      not timestamps_equal?(booking.start_time, new_start) or
      not timestamps_equal?(booking.end_time, new_end)
  end

  defp timestamps_equal?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq

  defp timestamps_equal?(%DateTime{} = a, b) when is_binary(b) do
    case DateTime.from_iso8601(b) do
      {:ok, parsed_b, _offset} -> DateTime.compare(a, parsed_b) == :eq
      _ -> false
    end
  end

  defp timestamps_equal?(a, b), do: a == b

  defp fetch_param(params, key, default) do
    case Map.fetch(params, key) do
      {:ok, val} -> val
      :error -> Map.get(params, Atom.to_string(key), default)
    end
  end
end
