defmodule AshPhoenixStarter.Bookings.Types.HotelRoomHandler do
  use AshPhoenixStarter.Bookings.BookingHandler

  alias AshPhoenixStarter.Hotels.Reservation
  alias AshPhoenixStarter.Properties.Unit

  require Ash.Query

  @impl true
  def validate_custom_rules(changeset, _actor), do: changeset

  @impl true
  def on_booked(booking, actor) do
    booking = Ash.load!(booking, [:resource], authorize?: false)
    tenant = Map.get(booking.__metadata__, :tenant)
    unit_id = extract_unit_id(booking.resource)
    property_id = extract_property_id(booking.resource)

    if unit_id do
      attrs = %{
        confirmation_code: generate_confirmation_code(),
        check_in_date: DateTime.to_date(booking.start_time),
        check_out_date: DateTime.to_date(booking.end_time),
        total_amount: Decimal.new("0.00"),
        property_id: property_id,
        property_unit_id: unit_id,
        booking_resource_id: booking.resource_id,
        user_id: booking.organizer_id || (actor && actor.id)
      }

      with {:ok, _reservation} <-
             Reservation
             |> Ash.Changeset.for_create(:create, attrs, tenant: tenant, authorize?: false)
             |> Ash.create() do
        mark_unit_status(unit_id, :reserved, tenant)
      end
    end

    notify_attendees(booking, :booked)
    {:ok, booking}
  end

  @impl true
  def on_updated(booking, _actor) do
    booking = Ash.load!(booking, [:resource], authorize?: false)
    tenant = Map.get(booking.__metadata__, :tenant)
    unit_id = extract_unit_id(booking.resource)

    if unit_id do
      sync_reservation_dates(booking, unit_id, tenant)
    end

    notify_attendees(booking, :updated)
    {:ok, booking}
  end

  @impl true
  def on_cancelled(booking, _actor) do
    booking = Ash.load!(booking, [:resource], authorize?: false)
    tenant = Map.get(booking.__metadata__, :tenant)
    unit_id = extract_unit_id(booking.resource)

    if unit_id do
      cancel_matching_reservation(booking, unit_id, tenant)
      mark_unit_status(unit_id, :available, tenant)
    end

    notify_attendees(booking, :cancelled)
    {:ok, booking}
  end

  defp extract_unit_id(nil), do: nil

  defp extract_unit_id(resource) do
    resource.property_unit_id ||
      get_in(resource.metadata || %{}, ["property_unit_id"]) ||
      get_in(resource.metadata || %{}, [:property_unit_id])
  end

  defp extract_property_id(nil), do: nil

  defp extract_property_id(resource) do
    get_in(resource.metadata || %{}, ["property_id"]) ||
      get_in(resource.metadata || %{}, [:property_id])
  end

  defp sync_reservation_dates(booking, unit_id, tenant) do
    query =
      Reservation
      |> Ash.Query.filter(
        property_unit_id == ^unit_id and
          booking_resource_id == ^booking.resource_id and
          status in [:reserved, :confirmed]
      )
      |> Ash.Query.limit(1)

    with {:ok, [reservation]} <- Ash.read(query, tenant: tenant, authorize?: false) do
      reservation
      |> Ash.Changeset.for_update(
        :update,
        %{
          check_in_date: DateTime.to_date(booking.start_time),
          check_out_date: DateTime.to_date(booking.end_time)
        },
        tenant: tenant,
        authorize?: false
      )
      |> Ash.update()
    end
  end

  defp cancel_matching_reservation(booking, unit_id, tenant) do
    query =
      Reservation
      |> Ash.Query.filter(
        property_unit_id == ^unit_id and
          booking_resource_id == ^booking.resource_id and
          status in [:reserved, :confirmed]
      )
      |> Ash.Query.limit(1)

    with {:ok, [reservation]} <- Ash.read(query, tenant: tenant, authorize?: false) do
      reservation
      |> Ash.Changeset.for_update(:cancel, %{}, tenant: tenant, authorize?: false)
      |> Ash.update()
    end
  end

  defp generate_confirmation_code do
    "HTL-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16())
  end

  defp mark_unit_status(unit_id, status, tenant) do
    with {:ok, unit} <- Ash.get(Unit, unit_id, tenant: tenant, authorize?: false) do
      unit
      |> Ash.Changeset.for_update(:update, %{status: status}, tenant: tenant, authorize?: false)
      |> Ash.update()
    end
  end
end
