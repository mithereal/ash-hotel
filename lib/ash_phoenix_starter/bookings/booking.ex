defmodule AshPhoenixStarter.Bookings.Booking do
  use Ash.Resource,
    otp_app: :AshPhoenixStarter,
    domain: AshPhoenixStarter.Bookings,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "bookings"
    repo AshPhoenixStarter.Repo

    # 1. Tell AshPostgres how to handle errors raised by your exclusion constraint
    #    exclusion_constraint_names [
    #      {:start_time, "bookings_no_overlapping_times",
    #       "This time slot overlaps with an existing booking"}
    #    ]

    # 2. Define the actual PostgreSQL exclusion constraint for migrations
    #    custom_statements do
    #      statement :bookings_no_overlapping_times do
    #        up """
    #        CREATE EXTENSION IF NOT EXISTS btree_gist;
    #        ALTER TABLE bookings
    #        ADD CONSTRAINT bookings_no_overlapping_times
    #        EXCLUDE USING gist (
    #          resource_id WITH =,
    #          tstzrange(start_time, end_time) WITH &&
    #        )
    #        WHERE (status != 'cancelled');
    #        """
    #
    #        down """
    #        ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_no_overlapping_times;
    #        """
    #      end

    #      references do
    #        # When the parent resource is deleted, cascade delete its bookings
    #        reference :resource, on_delete: :delete
    #        reference :organizer, on_delete: :nothing
    #      end
    #    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:start_time, :end_time, :notes, :resource_id, :organizer_id]
      primary? true
    end

    update :update do
      require_atomic? false
      accept [:start_time, :end_time, :notes, :status, :organizer_id, :resource_id]
    end
  end

  preparations do
    prepare AshPhoenixStarter.Preparations.SetTenant
  end

  changes do
    change AshPhoenixStarter.Changes.SetTenant
  end

  validations do
    validate fn _changeset, context ->
      if context.actor do
        :ok
      else
        {:error, field: :base, message: "Unauthorized"}
      end
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id

    attribute :start_time, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :end_time, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :notes, :string

    attribute :status, :atom do
      constraints one_of: [:scheduled, :confirmed, :cancelled]
      default :scheduled
    end

    attribute :operational_modes, {:array, :atom} do
      constraints items: [one_of: [:hotel]]
      default [:hotel]
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :resource, AshPhoenixStarter.Bookings.Resource
    has_many :attendees, AshPhoenixStarter.Bookings.Attendee, destination_attribute: :booking_id
    belongs_to :organizer, AshPhoenixStarter.Accounts.User, attribute_type: :uuid
  end

  calculations do
    # Derived (never stored) from the associated Resource's metadata, so these
    # always reflect the resource's current metadata rather than a stale copy
    # taken at booking-creation time.
    calculate :property_id, :uuid, expr(type(resource.metadata[:property_id], :uuid))
    calculate :property_unit_id, :uuid, expr(type(resource.metadata[:property_unit_id], :uuid))
    calculate :contract_id, :uuid, expr(type(resource.metadata[:contract_id], :uuid))
end
