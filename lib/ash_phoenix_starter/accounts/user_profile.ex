defmodule AshPhoenixStarter.Accounts.UserProfile do
  use Ash.Resource,
    domain: AshPhoenixStarter.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "user_profiles"
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
        :first_name,
        :last_name,
        :company_name,
        :job_title,
        :phone_number,
        :mobile_number,
        :fax_number,
        :website,
        :mailing_address,
        :billing_address,
        :emergency_contact_name,
        :emergency_contact_phone,
        :emergency_contact_relationship,
        :tax_id,
        :notes,
        :user_id
      ]
    end

    update :update do
      accept [
        :first_name,
        :last_name,
        :company_name,
        :job_title,
        :phone_number,
        :mobile_number,
        :fax_number,
        :website,
        :mailing_address,
        :billing_address,
        :emergency_contact_name,
        :emergency_contact_phone,
        :emergency_contact_relationship,
        :tax_id,
        :notes
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :first_name, :string, allow_nil?: false
    attribute :last_name, :string, allow_nil?: true
    attribute :company_name, :string
    attribute :job_title, :string

    # Rolodex communication channels
    attribute :phone_number, :string
    attribute :mobile_number, :string
    attribute :fax_number, :string
    attribute :website, :string

    # Structured physical addresses stored as maps
    attribute :mailing_address, :map, default: %{}
    attribute :billing_address, :map, default: %{}

    # Emergency/Management metadata
    attribute :emergency_contact_name, :string
    attribute :emergency_contact_phone, :string
    attribute :emergency_contact_relationship, :string

    # Financial / Vendor compliance tracking
    attribute :tax_id, :string
    attribute :notes, :string

    timestamps()
  end

  relationships do
    belongs_to :user, AshPhoenixStarter.Accounts.User do
      source_attribute :user_id
      allow_nil? false
      attribute_writable? true
    end
  end
end
