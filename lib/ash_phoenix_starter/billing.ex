defmodule AshPhoenixStarter.Billing do
  use Ash.Domain,
    otp_app: :ash_phoenix_starter,
    extensions: [AshOps]

  resources do
    resource AshPhoenixStarter.Billing.TenantUsage
  end
end
