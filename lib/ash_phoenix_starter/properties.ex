defmodule AshPhoenixStarter.Properties do
  use Ash.Domain,
    otp_app: :AshPhoenixStarter

  resources do
    resource AshPhoenixStarter.Properties.Property
    resource AshPhoenixStarter.Properties.Account
    resource AshPhoenixStarter.Properties.Feature
    resource AshPhoenixStarter.Properties.Service
    resource AshPhoenixStarter.Properties.Unit
    resource AshPhoenixStarter.Properties.Unit.Account
    resource AshPhoenixStarter.Properties.Unit.Feature
    resource AshPhoenixStarter.Properties.Unit.Service
    resource AshPhoenixStarter.Properties.Property.Image
    resource AshPhoenixStarter.Properties.UnitImage
  end
end
