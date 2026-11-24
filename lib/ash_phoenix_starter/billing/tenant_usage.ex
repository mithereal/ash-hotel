defmodule AshPhoenixStarter.Billing.TenantUsage do
  use Ash.Resource,
    domain: AshPhoenixStarter.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tenant_usages"
    repo AshPhoenixStarter.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :region_id, :string, allow_nil?: false, default: "global", public?: true
    # First day of the billing month (e.g., ~D[2026-11-01])
    attribute :period_start, :date, allow_nil?: false, public?: true

    attribute :storage_bytes, :integer, allow_nil?: false, default: 0, public?: true
    attribute :bandwidth_bytes, :integer, allow_nil?: false, default: 0, public?: true

    # Per-hotel monthly limits (defaults: 5 GB storage, 50 GB bandwidth)
    attribute :storage_limit_bytes, :integer,
      allow_nil?: false,
      default: 5 * 1024 * 1024 * 1024,
      public?: true

    attribute :bandwidth_limit_bytes, :integer,
      allow_nil?: false,
      default: 50 * 1024 * 1024 * 1024,
      public?: true

    timestamps()
  end

  identities do
    identity :unique_period, [:organization_id, :region_id, :period_start]
  end

  actions do
    defaults [:read, :update]

    create :seed_new_period do
      accept [
        :organization_id,
        :region_id,
        :period_start,
        :storage_bytes,
        :storage_limit_bytes,
        :bandwidth_limit_bytes
      ]

      upsert? true
      upsert_identity :unique_period
      # If two nodes race on the 1st of the month, keep the existing row untouched
      upsert_fields []

      change set_attribute(:bandwidth_bytes, 0)
    end

    create :set_limits do
      accept [:organization_id, :region_id, :period_start, :storage_limit_bytes, :bandwidth_limit_bytes]

      upsert? true
      upsert_identity :unique_period
      upsert_fields [:storage_limit_bytes, :bandwidth_limit_bytes, :updated_at]
    end

    read :latest_for_tenant do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :region_id, :string, allow_nil?: false

      filter expr(
               organization_id == ^arg(:organization_id) and
                 region_id == ^arg(:region_id)
             )

      prepare build(sort: [period_start: :desc], limit: 1)
    end    

    read :for_current_period do
      get? true
      argument :organization_id, :uuid, allow_nil?: false
      argument :region_id, :string, allow_nil?: false
      argument :period_start, :date, allow_nil?: false
      attribute :reported_overage_gb, :integer, allow_nil?: false, default: 0, public?: true

      filter expr(
               organization_id == ^arg(:organization_id) and
                 region_id == ^arg(:region_id) and
                 period_start == ^arg(:period_start)
             )
    end

    create :record_delta do
      accept [:organization_id, :region_id, :period_start]
      argument :storage_delta, :integer, default: 0
      argument :bandwidth_delta, :integer, default: 0

      upsert? true
      upsert_identity :unique_period

      # Atomic SQL increment so multi-node flushes never race
      upsert_fields [
        storage_bytes: expr(fragment("GREATEST(0, ? + ?)", storage_bytes, ^arg(:storage_delta))),
        bandwidth_bytes:
          expr(fragment("GREATEST(0, ? + ?)", bandwidth_bytes, ^arg(:bandwidth_delta))),
        updated_at: expr(now())
      ]

      change set_attribute(:storage_bytes, arg(:storage_delta))
      change set_attribute(:bandwidth_bytes, arg(:bandwidth_delta))
    end
  end
end
