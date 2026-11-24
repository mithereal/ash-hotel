defmodule AshPhoenixStarter.Subscriptions.Subscription do
  use Ash.Resource,
    domain: AshPhoenixStarter.Subscriptions,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "subscriptions"
    repo AshPhoenixStarter.Repo

    references do
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
        :name,
        :ends_at,
        :trial_ends_at,
        :stripe_id,
        :stripe_status,
        :customer_id,
        :customer_type
      ]

      argument :organization_id, :uuid, allow_nil?: false
      change manage_relationship(:organization_id, :organization, type: :append_and_remove)
    end

    update :update do
      accept [
        :name,
        :ends_at,
        :trial_ends_at,
        :stripe_id,
        :stripe_status
      ]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :ends_at, :utc_datetime
    attribute :trial_ends_at, :utc_datetime
    attribute :stripe_id, :string
    attribute :stripe_status, :string

    # Retaining customer fields for compatibility with polymorphic/existing associations
    attribute :customer_id, :integer

    attribute :customer_type, :string do
      default "user"
    end

    attribute :organization_id, :uuid, allow_nil?: false

    timestamps type: :utc_datetime
  end

  relationships do
    belongs_to :organization, AshPhoenixStarter.Accounts.Organization do
      allow_nil? false
      attribute_writable? true

      # Maps the foreign key to customer_id if you want to tie it directly to the organization identifier,
      # or you can rely on organization_id depending on your exact database column setup.
    end

    has_many :subscription_items, AshPhoenixStarter.Subscriptions.SubscriptionItem
  end
end
