defmodule AshPhoenixStarter.Hotels.Service do
  use Ash.Resource,
    domain: AshPhoenixStarter.Hotels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "hotel_services"
    repo AshPhoenixStarter.Repo

    references do
      reference :hotel, on_delete: :delete
      reference :service, on_delete: :nothing
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
      accept [:hotel_id, :service_id, :custom_price, :active]
    end

    update :update do
      accept [:custom_price, :active]
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
    attribute :custom_price, :decimal
    attribute :active, :boolean, default: true, allow_nil?: false

    attribute :hotel_id, :uuid, allow_nil?: false
    attribute :service_id, :uuid, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :hotel, AshPhoenixStarter.Hotels.Hotel do
      source_attribute :hotel_id
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :service, AshPhoenixStarter.Core.Service do
      source_attribute :service_id
      allow_nil? false
      attribute_writable? true
      destination_attribute :id
    end
  end
end
