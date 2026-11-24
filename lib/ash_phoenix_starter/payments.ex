defmodule AshPhoenixStarter.Payments do
  use Ash.Domain,
    otp_app: :AshPhoenixStarter

  resources do
    resource AshPhoenixStarter.Payments.Payment
    resource AshPhoenixStarter.Payments.Invoices.Invoice
    resource AshPhoenixStarter.Payments.Plugin
    resource AshPhoenixStarter.Payments.PropertyGateway
    resource AshPhoenixStarter.Payments.Transaction
  end
end
