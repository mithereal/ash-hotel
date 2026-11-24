defmodule AshPhoenixStarter.Hotels.Units do
  use Ash.Resource,
    domain: AshPhoenixStarter.Hotels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "hotel_units"
    repo AshPhoenixStarter.Repo

    references do
      reference :hotel, on_delete: :delete
      reference :unit, on_delete: :nothing
    end
  end

  code_interface do
    define :get_by_id, action: :read, get_by: [:id]
    define :list_units, action: :read
    define :create_unit, action: :create
    define :update_unit, action: :update
    define :mark_dirty, action: :mark_dirty
    define :mark_clean, action: :mark_clean
    define :place_out_of_order, action: :place_out_of_order
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
    end

    create :create do
      primary? true

      accept [
        :hotel_id,
        :unit_id,
        :notes,
        :floor,
        :nightly_rate,
        :max_occupancy,
        :bed_configuration,
        :is_bookable_online,
        :status,
        :housekeeping_status
      ]

      change AshPhoenixStarter.Changes.CreateBookingResourceForUnit
    end

    update :update do
      accept [
        :hotel_id,
        :unit_id,
        :notes,
        :floor,
        :nightly_rate,
        :max_occupancy,
        :bed_configuration,
        :is_bookable_online,
        :status,
        :housekeeping_status
      ]
    end

    update :mark_dirty do
      accept []
      change set_attribute(:housekeeping_status, :dirty)
    end

    update :mark_clean do
      accept []
      change set_attribute(:housekeeping_status, :clean)
      change set_attribute(:status, :available)
    end

    update :place_out_of_order do
      accept []
      change set_attribute(:status, :maintenance)
      change set_attribute(:housekeeping_status, :out_of_order)
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
    attribute :unit_id, :uuid, allow_nil?: false
    attribute :notes, :string
    attribute :floor, :integer
    attribute :nightly_rate, :string
    attribute :max_occupancy, :integer
    attribute :bed_configuration, :float
    attribute :is_bookable_online, :boolean
    attribute :status, :atom
    attribute :housekeeping_status, :atom

    timestamps()
  end

  relationships do
    belongs_to :hotel, AshPhoenixStarter.Hotels.Hotel do
      source_attribute :hotel_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :unit, AshPhoenixStarter.Properties.Unit do
      source_attribute :unit_id
      allow_nil? false
      attribute_writable? true
      destination_attribute :id
    end
  end
end
