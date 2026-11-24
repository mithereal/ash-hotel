defmodule AshPhoenixStarter.Payments.Invoices.Invoice do
  @moduledoc """
  the invoice will act like a snapshot of the ledger for a point in time, telling the customer what to pay
  """
  use Ash.Resource,
    domain: Elixir.AshPhoenixStarter.Payments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "invoices"
    repo AshPhoenixStarter.Repo

    references do
      reference :account, on_delete: :nothing
      reference :user, on_delete: :nothing
    end
  end

  code_interface do
    define :create_invoice, action: :create
    define :issue_invoice, action: :issue
    define :pay_invoice, action: :pay
    define :void_invoice, action: :void
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :invoice_number,
        :title,
        :description,
        :amount,
        :currency,
        :due_date,
        :account_id,
        :user_id
      ]

      change set_attribute(:status, :draft)
    end

    update :issue do
      accept []
      change set_attribute(:status, :issued)
    end

    update :pay do
      accept []
      change set_attribute(:status, :paid)
      change set_attribute(:paid_at, &DateTime.utc_now/0)
    end

    update :void do
      accept []
      change set_attribute(:status, :void)
    end
  end

  policies do
    policy always() do
      access_type :strict
      authorize_if AshPhoenixStarter.Accounts.Checks.Authorize
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
    uuid_v7_primary_key :id

    attribute :invoice_number, :string do
      allow_nil? false
    end

    attribute :title, :string do
      allow_nil? false
    end

    attribute :type, :atom do
      constraints one_of: [:work_order, :reservation, :tenancy, :tenant_screening]
      default :tenancy
      allow_nil? false
    end

    attribute :description, :string

    attribute :amount, :money do
      allow_nil? false
      constraints storage_type: :money_with_currency
    end

    attribute :currency, :string do
      allow_nil? false
      default "USD"
    end

    attribute :status, :atom do
      constraints one_of: [:draft, :issued, :paid, :void, :overdue]
      default :draft
      allow_nil? false
    end

    attribute :due_date, :date do
      allow_nil? false
    end

    attribute :paid_at, :utc_datetime_usec
    attribute :account_id, :uuid_v7, allow_nil?: false
    attribute :type_id, :uuid
    attribute :user_id, :uuid, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :account, AshPhoenixStarter.Ledgers.Account do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :user, AshPhoenixStarter.Accounts.User do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_invoice_number, [:invoice_number]
  end
end
