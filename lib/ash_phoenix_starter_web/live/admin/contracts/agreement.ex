defmodule Platform.Contracts.Agreement do
  use Ash.Resource,
    domain: Platform.Contracts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "contract_agreements"
    repo Platform.Repo
  end

  graphql do
    type :contract_agreement

    mutations do
      create :issue_contract, :create
      update :sign_contract, :sign
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:subject_type, :subject_id, :signer_id, :terms_snapshot]
    end

    update :sign do
      accept [:signature_data_url]
      change set_attribute(:status, :signed)
      change set_attribute(:signed_at, &DateTime.utc_now/0)
    end
  end

  pub_sub do
    module PlatformWeb.Endpoint
    prefix "contracts"
    publish :sign, ["signed"]
  end

  attributes do
    uuid_primary_key :id
    attribute :subject_type, :string, allow_nil?: false, public?: true
    attribute :subject_id, :uuid, allow_nil?: false, public?: true
    attribute :signer_id, :uuid, allow_nil?: false, public?: true
    attribute :terms_snapshot, :string, allow_nil?: false, public?: true
    attribute :signature_data_url, :string, public?: true
    attribute :signed_at, :utc_datetime_usec, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:pending, :signed, :void]],
      default: :pending,
      public?: true

    timestamps()
  end
end
