defmodule AshPhoenixStarter.Contracts.Contract do
  use Ash.Resource,
    domain: AshPhoenixStarter.Contracts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "contracts"
    repo AshPhoenixStarter.Repo

    references do
      reference :property, on_delete: :delete
      reference :property_unit, on_delete: :delete
      reference :user, on_delete: :nothing
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
      accept [:title, :document_content, :status, :property_id, :property_unit_id, :user_id]
      change set_attribute(:status, :draft)
    end

    update :update do
      accept [:title, :document_content, :status]
      require_atomic? false
    end

    update :publish do
      change set_attribute(:status, :pending_signature)
      require_atomic? false
    end

    update :execute do
      change set_attribute(:status, :active)
      require_atomic? false
    end
  end

  preparations do
    prepare AshPhoenixStarter.Preparations.SetTenant
  end

  changes do
    change AshPhoenixStarter.Changes.SetTenant
    change AshPhoenixStarter.Changes.CreateBookingResourceForContract
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :document_content, :map, default: %{}
    attribute :type, :string, default: "lease"

    attribute :status, :atom do
      constraints one_of: [:draft, :pending_signature, :active, :terminated, :expired]
      default :draft
      allow_nil? false
    end

    attribute :property_id, :uuid, allow_nil?: true
    attribute :property_unit_id, :uuid, allow_nil?: true
    attribute :user_id, :uuid, allow_nil?: true

    timestamps()
  end

  # Encapsulated module functions for modifications
  def publish_contract(contract, actor \\ nil) do
    contract
    |> Ash.Changeset.for_update(:publish, %{}, actor: actor)
    |> Ash.update()
  end

  def execute_contract(contract, actor \\ nil) do
    contract
    |> Ash.Changeset.for_update(:execute, %{}, actor: actor)
    |> Ash.update()
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

    belongs_to :user, AshPhoenixStarter.Accounts.User do
      source_attribute :user_id
      allow_nil? true
      attribute_writable? true
    end

    has_many :signatures, AshPhoenixStarter.Contracts.ContractSignature
  end
end
