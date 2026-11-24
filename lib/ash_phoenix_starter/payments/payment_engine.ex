defmodule AshPhoenixStarter.Payments.PaymentEngine do
  @moduledoc """
  Enhanced payment engine bridging payments, invoices, and double-entry ledger transfers.
  Automatically settles invoices and reconciles the ledger entries when a payment is processed.
  """

  alias AshPhoenixStarter.Payments.Payment
  alias AshPhoenixStarter.Payments.Invoice
  alias AshPhoenixStarter.Ledgers.Transfer
  alias AshPhoenixStarter.Core.QuickBooksAdapter
  alias Money

  import Ash.Query

  def process_payment(attrs, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)
    actor = Keyword.get(opts, :actor)
    resolved_tenant = resolve_tenant(tenant, actor, attrs)

    amount = attrs[:amount] || attrs["amount"] || Decimal.new("0.00")
    currency = attrs[:currency] || attrs["currency"] || :USD
    money_amount = Money.new!(amount, currency)
    invoice_id = attrs[:invoice_id] || attrs["invoice_id"]

    context =
      [{:tenant, resolved_tenant}, {:actor, actor}] |> Enum.reject(fn {_, v} -> is_nil(v) end)

    Ash.transaction(resolved_tenant, fn ->
      with {:ok, payment} <- create_payment_record(attrs, resolved_tenant, actor),
           {:ok, _transfer} <- post_ledger_transfer(payment, money_amount, context),
           {:ok, _invoice} <- maybe_mark_invoice_paid(invoice_id, context),
           :ok <- maybe_sync_accounting(resolved_tenant, payment) do
        payment
      else
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp create_payment_record(attrs, tenant, actor) do
    context = [{:tenant, tenant}, {:actor, actor}] |> Enum.reject(fn {_, v} -> is_nil(v) end)
    payment_attrs = maybe_put_organization_id(attrs, tenant)

    Payment
    |> Ash.Changeset.for_create(:create, payment_attrs, context)
    |> Ash.create(context)
  end

  defp post_ledger_transfer(payment, money_amount, context) do
    from_account_id = resolve_payer_account(payment)
    to_account_id = resolve_gateway_clearing_account(payment.processor)

    Transfer
    |> Ash.Changeset.for_create(
      :transfer,
      %{
        amount: money_amount,
        from_account_id: from_account_id,
        to_account_id: to_account_id,
        timestamp: payment.paid_at || DateTime.utc_now()
      },
      context
    )
    |> Ash.create(context)
  end

  defp maybe_mark_invoice_paid(nil, _context), do: {:ok, nil}

  defp maybe_mark_invoice_paid(invoice_id, context) do
    case Ash.get(Invoice, invoice_id, context) do
      {:ok, invoice} ->
        invoice
        |> Ash.Changeset.for_update(:pay, %{}, context)
        |> Ash.update(context)

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_sync_accounting(tenant_id, payment) do
    if payment.status == :succeeded do
      case QuickBooksAdapter.sync_payment(tenant_id, payment) do
        {:ok, _response} -> :ok
        {:error, {:quickbooks_not_configured, _}} -> :ok
        {:error, reason} -> {:error, {:accounting_sync_failed, reason}}
      end
    else
      :ok
    end
  end

  defp resolve_tenant(tenant, actor, attrs \\ [])

  defp resolve_tenant(nil, %{current_organization: organization}, _attrs)
       when not is_nil(organization), do: organization

  defp resolve_tenant(nil, _actor, %{organization_id: organization_id}), do: organization_id
  defp resolve_tenant(nil, _actor, %{"organization_id" => organization_id}), do: organization_id
  defp resolve_tenant(tenant, _actor, _attrs), do: tenant

  defp maybe_put_organization_id(attrs, nil), do: attrs

  defp maybe_put_organization_id(attrs, tenant) do
    attrs
    |> Map.put_new(:organization_id, tenant)
    |> Map.put_new("organization_id", tenant)
  end

  defp resolve_payer_account(payment) do
    case payment.payment_type do
      :rent -> "tenant-rent-receivable-account-uuid"
      :maintenance_fee -> "tenant-maintenance-receivable-account-uuid"
      _ -> "mock-tenant-ar-clearing-account-uuid"
    end
  end

  defp resolve_gateway_clearing_account(processor) do
    case processor do
      :stripe -> "mock-stripe-clearing-account-uuid"
      :zelle -> "mock-zelle-clearing-account-uuid"
      :ach -> "mock-ach-clearing-account-uuid"
      _ -> "mock-general-bank-clearing-account-uuid"
    end
  end

  @doc """
  Retrieves a payment by its primary ID within a specified tenant scope.
  """
  @spec get_payment(String.t(), keyword()) :: {:ok, Payment.t()} | {:error, term()}
  def get_payment(payment_id, opts \\ []) do
    tenant = Keyword.get(opts, :tenant)
    actor = Keyword.get(opts, :actor)
    resolved_tenant = resolve_tenant(tenant, actor)

    query =
      Payment
      |> filter(id == ^payment_id)
      |> maybe_set_tenant(resolved_tenant)

    context = build_context(resolved_tenant, actor)

    case Ash.read_one(query, context) do
      {:ok, nil} -> {:error, :payment_not_found}
      {:ok, payment} -> {:ok, payment}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all payments for a tenant with optional filtering by status or processor.
  """
  @spec list_payments(keyword(), keyword()) :: {:ok, [Payment.t()]} | {:error, term()}
  def list_payments(filters \\ [], opts \\ []) do
    tenant = Keyword.get(opts, :tenant)
    actor = Keyword.get(opts, :actor)
    resolved_tenant = resolve_tenant(tenant, actor)

    query =
      Payment
      |> apply_filters(filters)
      |> maybe_set_tenant(resolved_tenant)

    context = build_context(resolved_tenant, actor)

    case Ash.read(query, context) do
      {:ok, payments} -> {:ok, payments}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Internal Helpers ---

  defp maybe_set_tenant(query, nil), do: query
  defp maybe_set_tenant(query, tenant), do: set_tenant(query, tenant)

  defp build_context(tenant, actor) do
    []
    |> maybe_add_to_context(:tenant, tenant)
    |> maybe_add_to_context(:actor, actor)
  end

  defp maybe_add_to_context(keyword_list, _key, nil), do: keyword_list
  defp maybe_add_to_context(keyword_list, key, value), do: Keyword.put(keyword_list, key, value)

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, status}, q -> filter(q, status == ^status)
      {:processor, processor}, q -> filter(q, processor == ^processor)
      {:property_id, prop_id}, q -> filter(q, property_id == ^prop_id)
      _, q -> q
    end)
  end
end
