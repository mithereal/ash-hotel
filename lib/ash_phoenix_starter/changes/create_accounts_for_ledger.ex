defmodule AshPhoenixStarter.Changes.CreateAccountsForLedger do
  use Ash.Resource.Change

  alias AshPhoenixStarter.Ledgers.Account
  import Ash.Query

  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, organization ->
      tenant = organization.domain

      attributes = []

      list =
        Enum.map(attributes, fn x ->
          Account
          |> Ash.Changeset.for_create(:open, x, tenant: tenant)
          |> Ash.create(tenant: tenant)
        end)

      {:ok, organization}
    end)
  end

  def atomic(_changeset, _opts, _context) do
    {:not_atomic, "CreateAccountsForLedger does not support atomic execution"}
  end
end
