defmodule AshPhoenixStarter.Payments.Invoices.Actions.GenerateFromLedger do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    tenant =
      Keyword.get(context, :tenant) || (context[:actor] && context[:actor].current_organization)

    property_id = Ash.Changeset.get_attribute(changeset, :property_id)
    unit_id = Ash.Changeset.get_attribute(changeset, :property_unit_id)

    # 1. Resolve the homeowner's ledger account ID
    account_id = resolve_account_id(property_id, unit_id, tenant)

    # 2. Fetch the current outstanding balance or open charges from the ledger
    current_balance = fetch_ledger_balance(account_id, tenant)

    if Decimal.compare(current_balance, Decimal.new("0.00")) == :gt do
      money_amount = Money.new!(current_balance, :USD)

      changeset
      |> Ash.Changeset.force_change_attribute(:amount_due, money_amount)
      |> Ash.Changeset.force_change_attribute(:ledger_account_id, account_id)
    else
      Ash.Changeset.add_error(changeset,
        field: :base,
        message: "No outstanding balance found in the ledger to invoice."
      )
    end
  end

  defp resolve_account_id(property_id, unit_id, tenant) do
    cond do
      not is_nil(unit_id) -> get_account_id_for_unit(unit_id, tenant)
      not is_nil(property_id) -> get_account_id_for_property(property_id, tenant)
      true -> raise "Property or Unit required to generate invoice from ledger."
    end
  end

  defp fetch_ledger_balance(account_id, tenant) do
    # Query your AshPhoenixStarter.Ledgers.Balance or account summation query
    case AshPhoenixStarter.Ledgers.Balance
         |> Ash.Query.filter(account_id == ^account_id)
         |> Ash.read_one(tenant: tenant) do
      {:ok, %{balance: %Money{amount: amount}}} -> amount
      {:ok, nil} -> Decimal.new("0.00")
      _ -> Decimal.new("0.00")
    end
  end

  # Stubs for account lookups
  defp get_account_id_for_unit(_unit_id, _tenant), do: "account_id_stub"
  defp get_account_id_for_property(_property_id, _tenant), do: "account_id_stub"
end
