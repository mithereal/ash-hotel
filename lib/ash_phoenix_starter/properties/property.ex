defmodule AshPhoenixStarter.Properties.Property do
  use Ash.Resource,
    domain: AshPhoenixStarter.Properties,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "properties"
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

      accept [
        :name,
        :address_line1,
        :address_line2,
        :city,
        :state,
        :active,
        :postal_code,
        :country,
        :property_type,
        :operational_modes,
        :status,
        :year_built,
        :square_feet,
        :notes,
        :market_id,
        :owner_id,
        :primary_image_id,
        :secondary_image_id,
        :floorplan_image_id
      ]

      change AshPhoenixStarter.Changes.CreateBookingResourceForProperty
    end

    update :update do
      accept [
        :name,
        :address_line1,
        :address_line2,
        :active,
        :city,
        :state,
        :postal_code,
        :country,
        :property_type,
        :operational_modes,
        :status,
        :year_built,
        :square_feet,
        :notes,
        :market_id,
        :owner_id,
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
    attribute :name, :string, allow_nil?: false
    attribute :address_line1, :string, allow_nil?: false
    attribute :address_line2, :string
    attribute :city, :string, allow_nil?: false
    attribute :state, :string, allow_nil?: false
    attribute :postal_code, :string, allow_nil?: false
    attribute :country, :string, default: "USA", allow_nil?: false

    attribute :property_type, :atom do
      constraints one_of: [
                    :single_family_home,
                    :multi_family,
                    :condominium,
                    :condo_hotel,
                    :townhouse,
                    :mixed_use,
                    :commercial,
                    :industrial,
                    :land,
                    :hotel
                  ]

      default :single_family_home
      allow_nil? false
    end

    attribute :operational_modes, {:array, :atom} do
      constraints items: [one_of: [:rental, :hoa, :hotel]]
      default [:rental]
      allow_nil? false
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
      description "Property Active?"
    end

    attribute :status, :atom do
      constraints one_of: [
                    :available,
                    :vacant,
                    :occupied,
                    :maintenance,
                    :reserved,
                    :dirty,
                    :off_market,
                    :sold,
                    :archived
                  ]

      default :vacant
      allow_nil? false
    end

    attribute :year_built, :integer
    attribute :square_feet, :integer
    attribute :notes, :string
    attribute :primary_image_id, :uuid
    attribute :secondary_image_id, :uuid
    attribute :floorplan_image_id, :uuid

    attribute :market_id, :uuid, allow_nil?: false
    attribute :owner_id, :uuid, allow_nil?: true

    timestamps()
  end

  relationships do
    belongs_to :market, AshPhoenixStarter.Core.Market do
      source_attribute :market_id
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :owner, AshPhoenixStarter.Accounts.User do
      source_attribute :owner_id
      allow_nil? true
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

    has_many :images, AshPhoenixStarter.Properties.Property.Image do
      destination_attribute :property_id
    end

    has_many :units, AshPhoenixStarter.Properties.Unit
    has_many :payments, AshPhoenixStarter.Payments.Payment
    has_many :contracts, AshPhoenixStarter.Contracts.Contract
    has_many :reservations, AshPhoenixStarter.Hotels.Reservation

    many_to_many :accounts, AshPhoenixStarter.Ledgers.Account do
      through AshPhoenixStarter.Properties.Account
      source_attribute_on_join_resource :property_id
      destination_attribute_on_join_resource :account_id
      description "The financial account for this property record."
    end

    many_to_many :features, AshPhoenixStarter.Core.Feature do
      through AshPhoenixStarter.Properties.Feature
      source_attribute_on_join_resource :property_id
      destination_attribute_on_join_resource :feature_id
    end

    many_to_many :services, AshPhoenixStarter.Core.Service do
      through AshPhoenixStarter.Properties.Service
      source_attribute_on_join_resource :property_id
      destination_attribute_on_join_resource :service_id
    end
  end
end
