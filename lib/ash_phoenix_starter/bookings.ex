defmodule AshPhoenixStarter.Bookings do
  use Ash.Domain,
    otp_app: :AshPhoenixStarter,
    extensions: [AshOps]

  resources do
    resource AshPhoenixStarter.Bookings.Attendee
    resource AshPhoenixStarter.Bookings.Booking
    resource AshPhoenixStarter.Bookings.Resource
  end
end
