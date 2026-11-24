defmodule AshPhoenixStarter.Core.Feature do
  use Ash.Resource,
    domain: AshPhoenixStarter.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "features"
    repo AshPhoenixStarter.Repo

    references do
      reference :primary_image, on_delete: :nothing
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
    define :active, action: :active
  end

  actions do
    defaults [
      :destroy,
      create: [:name, :category, :description, :status, :primary_image_id],
      update: [:name, :category, :description, :status, :primary_image_id]
    ]

    read :read do
      primary? true
      # Enable pagination support (keyset or offset)
      pagination offset?: true, default_limit: 20, max_page_size: 100
    end

    read :list_all do
      # No pagination block or settings here means it returns a standard plain list
    end

    read :active do
      filter expr(status == :active)

      pagination offset?: true, default_limit: 20, max_page_size: 100
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :primary_image_id, :uuid

    attribute :category, :atom do
      constraints one_of: [:system, :amenity, :exterior, :utility, :security]
      default :system
      allow_nil? false
    end

    attribute :status, :atom do
      constraints one_of: [:active, :inactive]
      default :active
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    many_to_many :property_units, AshPhoenixStarter.Properties.Unit,
      through: AshPhoenixStarter.Properties.Unit.Feature,
      destination_attribute_on_join_resource: :property_unit_id,
      source_attribute_on_join_resource: :id

    many_to_many :properties, AshPhoenixStarter.Properties.Property,
      through: AshPhoenixStarter.Properties.Feature,
      destination_attribute_on_join_resource: :property_id,
      source_attribute_on_join_resource: :id

    belongs_to :primary_image, AshPhoenixStarter.Core.FileAsset do
      source_attribute :primary_image_id
      allow_nil? true
      attribute_writable? true
      destination_attribute :id
    end
  end
end
