defmodule AshPhoenixStarter.Hotels.Reservation do
  use Ash.Resource,
    domain: AshPhoenixStarter.Hotels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "hotel_reservations"
    repo AshPhoenixStarter.Repo

    references do
      reference :hotel, on_delete: :delete
      reference :user, on_delete: :delete
      reference :property, on_delete: :delete
      reference :property_unit, on_delete: :delete
      reference :booking_resource, on_delete: :delete
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

      accept [
        :confirmation_code,
        :check_in_date,
        :check_out_date,
        :adult_count,
        :child_count,
        :total_amount,
        :property_id,
        :property_unit_id,
        :booking_resource_id,
        :user_id
      ]

      change set_attribute(:status, :confirmed)
    end

    update :check_in do
      accept []
      change set_attribute(:status, :checked_in)
    end

    update :check_out do
      accept []
      change set_attribute(:status, :checked_out)
    end

    update :cancel do
      accept []
      change set_attribute(:status, :cancelled)
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
    attribute :confirmation_code, :string, allow_nil?: false
    attribute :check_in_date, :date, allow_nil?: false
    attribute :check_out_date, :date, allow_nil?: false
    attribute :adult_count, :integer, default: 1, allow_nil?: false
    attribute :child_count, :integer, default: 0, allow_nil?: false
    attribute :total_amount, :decimal, allow_nil?: false

    attribute :status, :atom do
      constraints one_of: [:reserved, :confirmed, :checked_in, :checked_out, :cancelled, :no_show]
      default :reserved
      allow_nil? false
    end

    attribute :property_id, :uuid, allow_nil?: true
    attribute :property_unit_id, :uuid, allow_nil?: true
    attribute :booking_resource_id, :uuid
    attribute :hotel_id, :uuid, allow_nil?: true
    attribute :user_id, :uuid

    timestamps()
  end

  relationships do
    belongs_to :property, AshPhoenixStarter.Properties.Property do
      source_attribute :property_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :property_unit, AshPhoenixStarter.Properties.Unit do
      source_attribute :property_unit_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :booking_resource, AshPhoenixStarter.Bookings.Resource do
      source_attribute :booking_resource_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :hotel, AshPhoenixStarter.Hotels.Hotel do
      source_attribute :hotel_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :user, AshPhoenixStarter.Accounts.User do
      source_attribute :user_id
      allow_nil? true
      attribute_writable? true
    end

    relationships do
      has_many :payments, AshPhoenixStarter.Payments.Payment do
        destination_attribute :reservation_id
      end
    end
  end
end
