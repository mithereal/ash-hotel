defmodule AshPhoenixStarter.Properties.Unit do
  use Ash.Resource,
    domain: AshPhoenixStarter.Properties,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "property_units"
    repo AshPhoenixStarter.Repo
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
    define :list_units, action: :read
    define :get_by_id, action: :read, get_by: [:id]
    define :create_unit, action: :create
    define :update_unit, action: :update
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :unit_number,
        :name,
        :floor,
        :square_feet,
        :bedrooms,
        :bathrooms,
        :unit_type,
        :status,
        :notes,
        :property_id,
        :active,
        :primary_image_id,
        :secondary_image_id,
        :floorplan_image_id
      ]

      change AshPhoenixStarter.Changes.CreateBookingResourceForUnit
    end

    update :update do
      accept [
        :unit_number,
        :name,
        :floor,
        :square_feet,
        :bedrooms,
        :bathrooms,
        :unit_type,
        :status,
        :notes,
        :active,
        :primary_image_id,
        :secondary_image_id,
        :floorplan_image_id
      ]
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
    attribute :unit_number, :string, allow_nil?: false
    attribute :name, :string, allow_nil?: false
    attribute :floor, :integer
    attribute :square_feet, :integer
    attribute :bedrooms, :decimal
    attribute :bathrooms, :decimal
    attribute :notes, :string

    attribute :primary_image_id, :uuid
    attribute :secondary_image_id, :uuid
    attribute :floorplan_image_id, :uuid

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
      description "Unit Active?"
    end

    attribute :unit_type, :atom do
      constraints one_of: [:residential, :commercial, :hotel_room, :suite, :penthouse]
      default :residential
      allow_nil? false
    end

    attribute :status, :atom do
      constraints one_of: [
                    :available,
                    :vacant,
                    :occupied,
                    :maintenance,
                    :reserved,
                    :dirty,
                    :off_market
                  ]

      default :vacant
      allow_nil? false
    end

    attribute :property_id, :uuid, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :property, AshPhoenixStarter.Properties.Property do
      source_attribute :property_id
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :primary_image, AshPhoenixStarter.Core.FileAsset do
      source_attribute :primary_image_id
      allow_nil? true
      attribute_writable? true
      destination_attribute :id
    end

    belongs_to :secondary_image, AshPhoenixStarter.Core.FileAsset do
      source_attribute :secondary_image_id
      allow_nil? true
      attribute_writable? true
      destination_attribute :id
    end

    belongs_to :floorplan_image, AshPhoenixStarter.Core.FileAsset do
      source_attribute :floorplan_image_id
      allow_nil? true
      attribute_writable? true
      destination_attribute :id
    end

    has_many :images, AshPhoenixStarter.Properties.UnitImage do
      destination_attribute :property_unit_id
    end

    # Domain Lifecycle Relationships (all keyed by property_unit_id)
    has_many :tenancies, AshPhoenixStarter.Rentals.Tenancy do
      destination_attribute :property_unit_id
    end

    has_many :reservations, AshPhoenixStarter.Hotels.Reservation do
      destination_attribute :property_unit_id
    end

    has_many :housekeeping_tasks, AshPhoenixStarter.Hotels.HousekeepingTask do
      destination_attribute :property_unit_id
    end

    has_many :contracts, AshPhoenixStarter.Contracts.Contract do
      destination_attribute :property_unit_id
    end

    has_many :payments, AshPhoenixStarter.Payments.Payment do
      destination_attribute :property_unit_id
    end

    many_to_many :accounts, AshPhoenixStarter.Ledgers.Account do
      through AshPhoenixStarter.Properties.Unit.Account
      source_attribute_on_join_resource :property_unit_id
      destination_attribute_on_join_resource :account_id
      description "The financial account for this unit record."
    end

    many_to_many :property_unit_features, AshPhoenixStarter.Core.Feature do
      through AshPhoenixStarter.Properties.Unit.Feature
      source_attribute_on_join_resource :property_unit_id
      destination_attribute_on_join_resource :feature_id
    end

    many_to_many :services, AshPhoenixStarter.Core.Service do
      through AshPhoenixStarter.Properties.Unit.Service
      source_attribute_on_join_resource :property_unit_id
      destination_attribute_on_join_resource :service_id
    end

    has_many :booking_resources, AshPhoenixStarter.Bookings.Resource do
      destination_attribute :property_unit_id
    end
  end
end
