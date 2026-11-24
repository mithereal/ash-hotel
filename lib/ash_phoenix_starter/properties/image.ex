defmodule AshPhoenixStarter.Properties.Property.Image do
  @moduledoc false
  use Ash.Resource,
    domain: AshPhoenixStarter.Properties,
    data_layer: AshPostgres.DataLayer

  alias AshPhoenixStarter.Core.FileAsset

  postgres do
    table "property_images"
    repo AshPhoenixStarter.Repo

    references do
      reference :property, on_delete: :delete
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
      accept [:property_id, :asset_id]
    end

    update :update do
      accept [:property_id, :asset_id]
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
    attribute :property_id, :uuid
    attribute :asset_id, :uuid, allow_nil?: false
  end

  relationships do
    belongs_to :property, AshPhoenixStarter.Properties.Property do
      source_attribute :property_id
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

defmodule AshPhoenixStarter.Properties.UnitImage do
  @moduledoc false
  use Ash.Resource,
    domain: AshPhoenixStarter.Properties,
    data_layer: AshPostgres.DataLayer

  alias AshPhoenixStarter.Core.FileAsset

  postgres do
    table "property_unit_images"
    repo AshPhoenixStarter.Repo
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:property_unit_id, :asset_id]
    end

    update :update do
      accept [:property_unit_id, :asset_id]
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
    attribute :property_unit_id, :uuid
    attribute :asset_id, :uuid, allow_nil?: false
  end

  relationships do
    belongs_to :property_unit, AshPhoenixStarter.Properties.Unit do
      source_attribute :property_unit_id
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
