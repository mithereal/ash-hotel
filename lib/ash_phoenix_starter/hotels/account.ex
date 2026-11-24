defmodule AshPhoenixStarter.Hotels.Account do
  use Ash.Resource,
    domain: AshPhoenixStarter.Hotels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "hotel_accounts"
    repo AshPhoenixStarter.Repo

    references do
      reference :hotel, on_delete: :delete
      reference :account, on_delete: :nothing
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
      accept [:account_id, :hotel_id]
    end

    update :update do
      accept [:account_id, :hotel_id]
    end
  end

  preparations do
    prepare AshPhoenixStarter.Preparations.SetTenant
  end

  changes do
    change AshPhoenixStarter.Changes.SetTenant
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id
    attribute :account_id, :uuid
    attribute :hotel_id, :uuid, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :account, AshPhoenixStarter.Ledgers.Account do
      source_attribute :account_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :hotel, AshPhoenixStarter.Hotels.Hotel do
      allow_nil? false
      attribute_writable? true
      source_attribute :hotel_id
    end
  end
end
