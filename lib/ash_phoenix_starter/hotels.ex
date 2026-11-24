defmodule AshPhoenixStarter.Hotels do
  use Ash.Domain,
    otp_app: :AshPhoenixStarter

  resources do
    resource AshPhoenixStarter.Hotels.Hotel
    resource AshPhoenixStarter.Hotels.Feature
    resource AshPhoenixStarter.Hotels.Properties
    resource AshPhoenixStarter.Hotels.Units
    resource AshPhoenixStarter.Hotels.Reservation
    resource AshPhoenixStarter.Hotels.Service
    resource AshPhoenixStarter.Hotels.Hotel.Image
  end
end
