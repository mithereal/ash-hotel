defmodule AshPhoenixStarter.Ledgers do
  use Ash.Domain,
    otp_app: :AshPhoenixStarter

  resources do
    resource AshPhoenixStarter.Ledgers.Account
    resource AshPhoenixStarter.Ledgers.Balance
    resource AshPhoenixStarter.Ledgers.Transfer
    resource AshPhoenixStarter.Ledgers.Description
  end
end
