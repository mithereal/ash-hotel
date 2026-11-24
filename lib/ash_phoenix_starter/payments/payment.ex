defmodule AshPhoenixStarter.Payments.Payment do
  use Ash.Resource,
    domain: AshPhoenixStarter.Payments,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "payments"
    repo AshPhoenixStarter.Repo

    references do
      reference :invoice, on_delete: :nothing
      reference :property, on_delete: :delete
      reference :property_unit, on_delete: :delete
      reference :user, on_delete: :nothing
      reference :reservation, on_delete: :nothing
      reference :booking, on_delete: :delete
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
        :amount,
        :currency,
        :processor,
        :status,
        :charge_id,
        :metadata,
        :property_id,
        :property_unit_id,
        :user_id,
        :booking_id,
        :reservation_id,
        :paid_at
      ]

      change set_attribute(:status, :succeeded)
      change set_attribute(:paid_at, &DateTime.utc_now/0)
    end

    update :update do
      accept [
        :amount,
        :status,
        :charge_id,
        :metadata
      ]
    end

    update :refund do
      accept []
      change set_attribute(:status, :refunded)
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
    attribute :amount, :decimal, allow_nil?: false
    attribute :currency, :atom, default: :USD, allow_nil?: false

    attribute :processor, :atom do
      constraints one_of: [
                    :stripe,
                    :zelle,
                    :ach,
                    :wire_transfer,
                    :paypal,
                    :venmo,
                    :check,
                    :cash,
                    :money_order
                  ]

      default :stripe
      allow_nil? false
    end

    attribute :payment_type, :atom do
      constraints one_of: [
                    :payment,
                    :security_deposit,
                    :maintenance_fee,
                    :application_fee,
                    :other
                  ]

      default :payment
      allow_nil? false
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :succeeded, :failed, :refunded, :disputed]
      default :pending
      allow_nil? false
    end

    # External gateway & accounting references
    attribute :charge_id, :uuid
    attribute :metadata, :map, default: %{}
    attribute :paid_at, :utc_datetime_usec
    attribute :property_id, :uuid
    attribute :property_unit_id, :uuid
    attribute :user_id, :uuid
    attribute :invoice_id, :uuid
    attribute :tenancy_id, :uuid
    attribute :booking_id, :uuid
    attribute :reservation_id, :uuid

    timestamps()
  end

  relationships do
    belongs_to :invoice, AshPhoenixStarter.Payments.Invoices.Invoice do
      source_attribute :invoice_id
      allow_nil? true
      attribute_writable? true
    end

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

    belongs_to :user, AshPhoenixStarter.Accounts.User do
      source_attribute :user_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :reservation, AshPhoenixStarter.AshPhoenixStarters.Reservation do
      source_attribute :reservation_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :booking, AshPhoenixStarter.Bookings.Booking do
      source_attribute :booking_id
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :work_order, AshPhoenixStarter.Vendors.WorkOrder do
      source_attribute :work_order_id
      allow_nil? true
      attribute_writable? true
    end
  end
end
