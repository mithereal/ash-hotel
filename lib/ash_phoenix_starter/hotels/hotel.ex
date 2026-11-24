defmodule AshPhoenixStarter.Hotels.Hotel do
  use Ash.Resource,
    domain: AshPhoenixStarter.Hotels,
    data_layer: AshPostgres.DataLayer

  require Ash.Resource.Change.Builtins

  postgres do
    table "hotel"
    repo AshPhoenixStarter.Repo
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      # Enable pagination support (keyset or offset)
      pagination offset?: true, default_limit: 20, max_page_size: 100
    end

    read :list_all do
      # No pagination block or settings here means it returns a standard plain list
    end

    create :create do
      accept [
        :name,
        :address_line1,
        :address_line2,
        :active,
        :city,
        :state,
        :postal_code,
        :country,
        :front_desk_phone,
        :reservation_email,
        :check_in_time,
        :check_out_time,
        :timezone,
        :star_rating,
        :owner_id,
        :status,
        :primary_image_id,
        :market_id
      ]
    end

    update :update do
      accept [
        :name,
        :market_id,
        :address_line1,
        :address_line2,
        :active,
        :city,
        :state,
        :status,
        :postal_code,
        :country,
        :front_desk_phone,
        :reservation_email,
        :check_in_time,
        :check_out_time,
        :timezone,
        :star_rating,
        :owner_id,
        :primary_image_id
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
    attribute :front_desk_phone, :string
    attribute :reservation_email, :string
    attribute :check_in_time, :time, default: ~T[15:00:00]
    attribute :check_out_time, :time, default: ~T[11:00:00]
    attribute :timezone, :string, default: "America/Phoenix"
    attribute :star_rating, :integer, constraints: [min: 1, max: 5]
    attribute :primary_image_id, :uuid
    attribute :secondary_image_id, :uuid
    attribute :floorplan_image_id, :uuid

    attribute :owner_id, :uuid
    attribute :market_id, :uuid

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
      description "Hotel Active?"
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
  end

  relationships do
    belongs_to :market, AshPhoenixStarter.Core.Market do
      source_attribute :market_id
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :owner, AshPhoenixStarter.Accounts.User do
      source_attribute :owner_id
      description "The user account who owns or manages this record."
    end

    many_to_many :accounts, AshPhoenixStarter.Ledgers.Account do
      through AshPhoenixStarter.Hotels.Account
      source_attribute_on_join_resource :hotel_id
      destination_attribute_on_join_resource :account_id
      description "The financial account for this hotel record."
    end

    many_to_many :properties, AshPhoenixStarter.Properties.Property do
      through AshPhoenixStarter.Hotels.Properties
      source_attribute_on_join_resource :hotel_id
      destination_attribute_on_join_resource :property_id
    end

    many_to_many :property_units, AshPhoenixStarter.Properties.Unit do
      through AshPhoenixStarter.Hotels.Units
      source_attribute_on_join_resource :hotel_id
      destination_attribute_on_join_resource :property_unit_id
    end

    many_to_many :services, AshPhoenixStarter.Core.Service do
      through AshPhoenixStarter.Hotels.Service
      source_attribute_on_join_resource :hotel_id
      destination_attribute_on_join_resource :service_id
    end

    many_to_many :features, AshPhoenixStarter.Core.Feature do
      through AshPhoenixStarter.Hotels.Feature
      source_attribute_on_join_resource :hotel_id
      destination_attribute_on_join_resource :feature_id
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

    has_many :images, AshPhoenixStarter.Hotels.Hotel.Image do
      destination_attribute :hotel_id
    end
  end
end
