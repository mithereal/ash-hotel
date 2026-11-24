defmodule AshPhoenixStarter.Contracts do
  use Ash.Domain,
    otp_app: :AshPhoenixStarter

  resources do
    resource AshPhoenixStarter.Contracts.Contract
    resource AshPhoenixStarter.Contracts.ContractSignature
  end
end
