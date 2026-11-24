defmodule AshPhoenixStarter.Hotels.HousekeepingTask do
  use Ash.Resource,
    domain: AshPhoenixStarter.Hotels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "hotel_housekeeping_tasks"
    repo AshPhoenixStarter.Repo

    references do
      reference :assigned_staff, on_delete: :nilify
      reference :room, on_delete: :delete
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
    define :active, action: :active
    define :pending, action: :pending
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [
      :destroy,
      create: [
        :title,
        :description,
        :priority,
        :status,
        :room_id,
        :assigned_staff_id,
        :scheduled_date
      ],
      update: [
        :title,
        :description,
        :priority,
        :status,
        :room_id,
        :assigned_staff_id,
        :scheduled_date,
        :completed_at
      ]
    ]

    read :read do
      primary? true
      pagination offset?: true, default_limit: 20, max_page_size: 100
    end

    read :active do
      filter expr(status in [:pending, :in_progress])
    end

    read :pending do
      filter expr(status == :pending)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false
    attribute :description, :string

    attribute :priority, :atom do
      constraints one_of: [:low, :medium, :high, :urgent]
      default :medium
      allow_nil? false
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :in_progress, :completed, :inspected, :cancelled]
      default :pending
      allow_nil? false
    end

    attribute :scheduled_date, :date
    attribute :completed_at, :utc_datetime

    attribute :room_id, :uuid, allow_nil?: false
    attribute :assigned_staff_id, :uuid

    timestamps()
  end

  relationships do
    belongs_to :room, AshPhoenixStarter.Hotels.Room do
      source_attribute :room_id
      destination_attribute :id
      allow_nil? false
    end

    belongs_to :assigned_staff, AshPhoenixStarter.Accounts.User do
      source_attribute :assigned_staff_id
      destination_attribute :id
      allow_nil? true
    end
  end
end
