defmodule AshPhoenixStarter.Core.Service do
  use Ash.Resource,
    domain: AshPhoenixStarter.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "services"
    repo AshPhoenixStarter.Repo

    references do
      reference :primary_image, on_delete: :nothing
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
  end

  actions do
    defaults [
      :destroy,
      create: [
        :name,
        :description,
        :default_price,
        :billing_frequency,
        :status,
        :primary_image_id
      ],
      update: [
        :name,
        :description,
        :default_price,
        :billing_frequency,
        :status,
        :primary_image_id
      ]
    ]

    read :read do
      primary? true
      # Enable pagination support (keyset or offset).
      # `required?: false` lets callers opt out with `page: false` when they
      # need a plain list (e.g. fetching a known set of ids by filter).
      pagination offset?: true, default_limit: 20, max_page_size: 100, required?: false
    end

    read :list_all do
      # No pagination block or settings here means it returns a standard plain list
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :default_price, :decimal, allow_nil?: false
    attribute :primary_image_id, :uuid

    attribute :billing_frequency, :atom do
      constraints one_of: [:monthly, :quarterly, :annually, :one_time]
      default :monthly
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
    many_to_many :properties, AshPhoenixStarter.Properties.Property,
      through: AshPhoenixStarter.Properties.Service,
      destination_attribute_on_join_resource: :property_id,
      source_attribute_on_join_resource: :service_id

    many_to_many :property_units, AshPhoenixStarter.Properties.Unit,
      through: AshPhoenixStarter.Properties.Unit.Service,
      destination_attribute_on_join_resource: :property_unit_id,
      source_attribute_on_join_resource: :service_id

    belongs_to :primary_image, AshPhoenixStarter.Core.FileAsset do
      source_attribute :primary_image_id
      allow_nil? true
      attribute_writable? true
      destination_attribute :id
    end
  end
end
