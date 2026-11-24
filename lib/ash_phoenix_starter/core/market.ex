defmodule AshPhoenixStarter.Core.Market do
  use Ash.Resource,
    domain: AshPhoenixStarter.Core,
    data_layer: AshPostgres.DataLayer

  require Ash.Resource.Change.Builtins

  postgres do
    table "market"
    repo AshPhoenixStarter.Repo

    references do
      reference :primary_image, on_delete: :nothing
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
  end

  actions do
    # Removed :domain from default_accept
    default_accept [:name, :city, :state, :status, :primary_image_id, :country]
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
      primary? true
    end

    update :update do
      # Removed :domain from accept list
      accept [:name, :city, :state, :status, :primary_image_id, :country]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Organization or organisation name"
    end

    # domain attribute removed entirely

    attribute :status, :atom do
      constraints one_of: [:active, :inactive]
      default :active
      allow_nil? false
    end

    attribute :city, :string, allow_nil?: true, public?: true
    attribute :state, :string, allow_nil?: true, public?: true
    attribute :country, :string, allow_nil?: true, public?: true
    attribute :primary_image_id, :uuid

    timestamps()
  end

  relationships do
    has_many :properties, AshPhoenixStarter.Properties.Property
    has_many :hotels, AshPhoenixStarter.Hotels.Hotel

    belongs_to :primary_image, AshPhoenixStarter.Core.FileAsset do
      source_attribute :primary_image_id
      allow_nil? true
      attribute_writable? true
      destination_attribute :id
    end
  end
end
