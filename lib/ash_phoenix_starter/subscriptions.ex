defmodule AshPhoenixStarter.Subscriptions do
  use Ash.Domain,
    otp_app: :AshPhoenixStarter,
    extensions: [AshOps]

  resources do
    resource AshPhoenixStarter.Subscriptions.Subscription
    resource AshPhoenixStarter.Subscriptions.SubscriptionItem
  end
end
