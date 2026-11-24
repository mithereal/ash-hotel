defmodule AshPhoenixStarter.Bookings.ResourceRegistry do
  @default_handlers %{
    hotel_room: AshPhoenixStarter.Bookings.Types.HotelRoomHandler,
    vendor: AshPhoenixStarter.Bookings.Types.VendorHandler,
    contract_signing: AshPhoenixStarter.Bookings.Types.ContractHandler,
    ticket: AshPhoenixStarter.Bookings.Types.TicketHandler,
    tenant_onboarding: AshPhoenixStarter.Bookings.Types.TenantHandler,
    property_viewing: AshPhoenixStarter.Bookings.Types.PropertyViewingHandler,
    property_manager_meeting: AshPhoenixStarter.Bookings.Types.DefaultHandler,
    owner_meeting: AshPhoenixStarter.Bookings.Types.DefaultHandler,
    general_meeting: AshPhoenixStarter.Bookings.Types.DefaultHandler,
    appointment: AshPhoenixStarter.Bookings.Types.DefaultHandler,
    move_out_inspection: AshPhoenixStarter.Bookings.Types.TenantHandler,
    amenity_reservation: AshPhoenixStarter.Bookings.Types.DefaultHandler
  }

  def handler_for(type) when is_atom(type) do
    configured = Application.get_env(:AshPhoenixStarter, :booking_handlers, %{})

    Map.get(
      Map.merge(@default_handlers, configured),
      type,
      AshPhoenixStarter.Bookings.Types.DefaultHandler
    )
  end
end
