defmodule AshPhoenixStarter.Bookings.CreationService do
  alias AshPhoenixStarter.Bookings.{
    Booking,
    BookingHandler,
    PubSub,
    Resource,
    ResourceRegistry,
    ValidationEngine
  }

  alias AshPhoenixStarter.Settings.Manager

  def create_booking(booking_params, resource_id, tenant, actor, notify \\ false) do
    max_hours = Manager.get_tenant(tenant, :max_booking_duration_hours)
    start_time = fetch_param(booking_params, :start_time)
    end_time = fetch_param(booking_params, :end_time)

    with {:ok, resource} <- Ash.get(Resource, resource_id, tenant: tenant, actor: actor),
         :ok <- ensure_active(resource),
         :ok <-
           ValidationEngine.validate_booking_slot(
             start_time,
             end_time,
             resource.type,
             resource.id,
             tenant: tenant,
             actor: actor,
             config: %{max_duration_hours: max_hours}
           ) do
      handler = ResourceRegistry.handler_for(resource.type)
      params = put_resource_id(booking_params, resource.id)

      changeset =
        Booking
        |> Ash.Changeset.for_create(:create, params, actor: actor, tenant: tenant)
        |> handler.validate_custom_rules(actor)

      case Ash.create(changeset, tenant: tenant, authorize?: false) do
        {:ok, booking} ->
          handler.on_booked(booking, actor)
          if notify, do: BookingHandler.notify_attendees(booking, :booked)
          PubSub.broadcast(tenant, :created, booking.id)
          {:ok, booking}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp ensure_active(%{active: true}), do: :ok
  defp ensure_active(_), do: {:error, "This booking resource is currently inactive."}

  defp fetch_param(params, key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp put_resource_id(params, resource_id) do
    if Enum.any?(Map.keys(params), &is_binary/1) do
      Map.put(params, "resource_id", resource_id)
    else
      Map.put(params, :resource_id, resource_id)
    end
  end
end
