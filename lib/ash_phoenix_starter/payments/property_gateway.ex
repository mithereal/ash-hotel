defmodule AshPhoenixStarter.Payments.PropertyGateway do
  use Ash.Resource,
    domain: AshPhoenixStarter.Payments.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "property_payment_gateways"
    repo AshPhoenixStarter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :configure do
      accept [
        :property_id,
        :provider_id,
        :label,
        :credentials,
        :supported_currencies,
        :is_default,
        :active
      ]

      upsert? true
      upsert_identity :unique_property_provider
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(property_id == ^actor(:property_id) or ^actor(:role) == :super_admin)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if expr(
                     (property_id == ^actor(:property_id) and
                        ^actor(:role) in [:property_admin, :manager]) or
                       ^actor(:role) == :super_admin
                   )
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :property_id, :uuid, allow_nil?: false, public?: true
    attribute :provider_id, :string, allow_nil?: false, public?: true
    attribute :label, :string, public?: true
    attribute :credentials, AshPhoenixStarter.Encrypted.Map, allow_nil?: false, sensitive?: true
    attribute :supported_currencies, {:array, :string}, default: [], public?: true
    attribute :is_default, :boolean, default: false, public?: true
    attribute :active, :boolean, default: true, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_property_provider, [:property_id, :provider_id]
  end
end
