defmodule AshPhoenixStarter.Contracts.ContractSignature do
  use Ash.Resource,
    domain: AshPhoenixStarter.Contracts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "contract_signatures"
    repo AshPhoenixStarter.Repo

    references do
      reference :contract, on_delete: :delete
      reference :user, on_delete: :nothing
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :sign do
      primary? true

      accept [
        :contract_id,
        :user_id,
        :signer_name,
        :signer_email,
        :signature_data,
        :ip_address,
        :user_agent
      ]

      change set_attribute(:signed_at, &DateTime.utc_now/0)
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
    attribute :signer_name, :string, allow_nil?: false
    attribute :signer_email, :string, allow_nil?: false

    # Can store a base64 data URL of a drawn signature (e.g., from a canvas pad)
    # or the typed legal full name string.
    attribute :signature_data, :string, allow_nil?: false, sensitive?: true

    # Legal compliance audit metadata
    attribute :ip_address, :string, allow_nil?: false
    attribute :user_agent, :string
    attribute :signed_at, :utc_datetime_usec, allow_nil?: false

    # Foreign keys
    attribute :contract_id, :uuid, allow_nil?: false
    # Optional if signed by a guest/non-portal user
    attribute :user_id, :uuid

    timestamps()
  end

  relationships do
    belongs_to :contract, AshPhoenixStarter.Contracts.Contract do
      source_attribute :contract_id
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :user, AshPhoenixStarter.Accounts.User do
      source_attribute :user_id
      allow_nil? true
      attribute_writable? true
    end
  end
end
