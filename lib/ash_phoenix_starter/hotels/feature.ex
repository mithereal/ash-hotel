defmodule AshPhoenixStarter.Hotels.Feature do
  use Ash.Resource,
    domain: AshPhoenixStarter.Hotels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "hotel_features"
    repo AshPhoenixStarter.Repo

    references do
      reference :hotel, on_delete: :delete
      reference :feature, on_delete: :nothing
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
      accept [:hotel_id, :feature_id, :notes]
    end

    update :update do
      accept [:hotel_id, :feature_id, :notes]
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
    attribute :hotel_id, :uuid
    attribute :feature_id, :uuid, allow_nil?: false
    attribute :notes, :string

    timestamps()
  end

  relationships do
    belongs_to :hotel, AshPhoenixStarter.Hotels.Hotel do
      source_attribute :hotel_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :feature, AshPhoenixStarter.Core.Feature do
      source_attribute :feature_id
      allow_nil? false
      attribute_writable? true
      destination_attribute :id
    end
  end
end
