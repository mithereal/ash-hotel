defmodule AshPhoenixStarter.Bookings.Attendee do
  use Ash.Resource,
    otp_app: :AshPhoenixStarter,
    domain: AshPhoenixStarter.Bookings,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "booking_attendees"
    repo AshPhoenixStarter.Repo

    references do
      reference :booking, on_delete: :delete
      reference :user, on_delete: :nothing
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :email, :phone, :user_id, :booking_id]
      primary? true
      require_attributes [:booking_id]
    end

    update :update do
      accept [:name, :email, :phone, :user_id]
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  preparations do
    prepare AshPhoenixStarter.Preparations.SetTenant
  end

  changes do
    change AshPhoenixStarter.Changes.SetTenant
  end

  validations do
    validate fn changeset, _context ->
      email = Ash.Changeset.get_attribute(changeset, :email)
      user_id = Ash.Changeset.get_attribute(changeset, :user_id)

      if (is_binary(email) and String.trim(email) != "") or not is_nil(user_id) do
        :ok
      else
        {:error, field: :email, message: "Either an email address or a user must be provided."}
      end
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :email, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :user_id, :uuid, public?: true
    attribute :booking_id, :uuid, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :booking, AshPhoenixStarter.Bookings.Booking, allow_nil?: false
    belongs_to :user, AshPhoenixStarter.Accounts.User, attribute_type: :uuid
  end
end
