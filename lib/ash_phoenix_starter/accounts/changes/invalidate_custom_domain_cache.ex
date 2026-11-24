defmodule AshPhoenixStarter.Accounts.Changes.InvalidateCustomDomainCache do
  @moduledoc """
  Ash `Change` that automatically invalidates `CustomDomainResolver` Nebulex cache
  entries whenever an `Organization`'s `custom_domain` or `slug` is created, updated,
  or destroyed.
  """
  use Ash.Resource.Change

  alias AshPhoenixStarter.Tenancy.CustomDomainResolver

  @impl true
  def change(changeset, _opts, _context) do
    previous_domain = changeset.data && Map.get(changeset.data, :custom_domain)

    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      current_domain = Map.get(record, :custom_domain)

      CustomDomainResolver.invalidate(previous_domain)

      if current_domain != previous_domain do
        CustomDomainResolver.invalidate(current_domain)
      end

      {:ok, record}
    end)
  end
end
