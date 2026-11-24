defmodule AshPhoenixStarter.Bookings.Resource do
  use Ash.Resource,
    otp_app: :AshPhoenixStarter,
    domain: AshPhoenixStarter.Bookings,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "booking_resources"
    repo AshPhoenixStarter.Repo
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
    end

    create :create do
      primary? true
      accept [:name, :description, :type, :active, :metadata, :property_unit_id]
    end

    update :update do
      accept [:name, :description, :type, :active, :metadata, :property_unit_id]
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
    attribute :description, :string

    attribute :type, :atom do
      constraints one_of: [
                    :hotel_room,
                    :property_viewing,
                    :appointment,
                    :property_manager_meeting,
                    :owner_meeting,
                    :general_meeting,
                    :vendor,
                    :contract_signing,
                    :ticket,
                    :tenant_onboarding,
                    :move_out_inspection,
                    :amenity_reservation
                  ]

      allow_nil? false
      default :appointment
    end

    attribute :property_unit_id, :uuid, allow_nil?: true
    attribute :metadata, :map, default: %{}
    attribute :active, :boolean, default: true, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :property_unit, AshPhoenixStarter.Properties.Unit do
      source_attribute :property_unit_id
      allow_nil? true
      attribute_writable? true
    end

    has_many :bookings, AshPhoenixStarter.Bookings.Booking
  end
end
