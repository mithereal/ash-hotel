defmodule AshPhoenixStarter.Subscriptions.SubscriptionItem do
  use Ash.Resource,
    domain: AshPhoenixStarter.Subscriptions,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "subscription_items"
    repo AshPhoenixStarter.Repo

    references do
      reference :subscription, on_delete: :delete
      reference :organization, on_delete: :delete
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :stripe_id,
        :stripe_product_id,
        :stripe_price_id,
        :quantity,
        :subscription_id
      ]

      argument :organization_id, :uuid, allow_nil?: false
      change manage_relationship(:organization_id, :organization, type: :append_and_remove)
    end

    update :update do
      accept [
        :stripe_id,
        :stripe_product_id,
        :stripe_price_id,
        :quantity
      ]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :stripe_id, :string
    attribute :stripe_product_id, :string
    attribute :stripe_price_id, :string
    attribute :quantity, :integer, default: 1

    attribute :subscription_id, :uuid, allow_nil?: false
    attribute :organization_id, :uuid, allow_nil?: false

    timestamps type: :utc_datetime
  end

  relationships do
    belongs_to :subscription, AshPhoenixStarter.Subscriptions.Subscription do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, AshPhoenixStarter.Accounts.Organization do
      allow_nil? false
      attribute_writable? true
    end
  end
end
