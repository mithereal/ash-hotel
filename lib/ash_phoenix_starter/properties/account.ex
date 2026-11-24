defmodule AshPhoenixStarter.Properties.Account do
  use Ash.Resource,
    domain: AshPhoenixStarter.Properties,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "property_accounts"
    repo AshPhoenixStarter.Repo

    references do
      reference :property, on_delete: :delete
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
      accept [:account_id, :property_id]
    end

    update :update do
      accept [:account_id, :property_id]
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
    attribute :property_id, :uuid, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :account, AshPhoenixStarter.Ledgers.Account do
      source_attribute :account_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :property, AshPhoenixStarter.Properties.Property do
      allow_nil? false
      attribute_writable? true
      source_attribute :property_id
    end
  end
end

defmodule AshPhoenixStarter.Properties.Unit.Account do
  use Ash.Resource,
    domain: AshPhoenixStarter.Properties,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "unit_accounts"
    repo AshPhoenixStarter.Repo

    references do
      reference :unit, on_delete: :delete
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
      accept [:account_id, :property_unit_id]
    end

    update :update do
      accept [:account_id, :property_unit_id]
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
    attribute :property_unit_id, :uuid, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :account, AshPhoenixStarter.Ledgers.Account do
      source_attribute :account_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :unit, AshPhoenixStarter.Properties.Unit do
      allow_nil? false
      attribute_writable? true
      source_attribute :property_unit_id
    end
  end
end
