defmodule AshPhoenixStarter.Hotels.Hotel.Image do
  @moduledoc false
  use Ash.Resource,
    domain: AshPhoenixStarter.Hotels,
    data_layer: AshPostgres.DataLayer

  alias AshPhoenixStarter.Core.FileAsset

  postgres do
    table "hotel_images"
    repo AshPhoenixStarter.Repo

    references do
      reference :hotel, on_delete: :delete
      reference :asset, on_delete: :nothing
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
      accept [:hotel_id, :asset_id]
    end

    update :update do
      accept [:hotel_id, :asset_id]
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
    attribute :asset_id, :uuid, allow_nil?: false
  end

  relationships do
    belongs_to :hotel, AshPhoenixStarter.Hotels.Hotel do
      source_attribute :hotel_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :asset, AshPhoenixStarter.Core.FileAsset do
      source_attribute :asset_id
      allow_nil? false
      attribute_writable? true
      destination_attribute :id
    end
  end
end
