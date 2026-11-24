defmodule AshPhoenixStarter.Bookings.Types.ContractHandler do
  @moduledoc """
  Booking lifecycle handler for contract execution and review sessions (:contract_signing).
  """
  use AshPhoenixStarter.Bookings.BookingHandler

  alias AshPhoenixStarter.Bookings.Resource
  alias AshPhoenixStarter.Contracts.Contract

  @impl true
  def validate_custom_rules(changeset, _actor) do
    tenant = changeset.tenant
    resource_id = Ash.Changeset.get_attribute(changeset, :resource_id)

    case fetch_contract_id(resource_id, tenant) do
      nil ->
        Ash.Changeset.add_error(
          changeset,
          field: :resource_id,
          message: "Contract signing session must be linked to a valid contract."
        )

      _contract_id ->
        changeset
    end
  end

  @impl true
  def on_booked(booking, actor) do
    booking = Ash.load!(booking, [:resource], authorize?: false)
    tenant = Map.get(booking.__metadata__, :tenant)
    contract_id = extract_contract_id(booking.resource)

    if contract_id do
      with {:ok, %Contract{status: :draft} = contract} <-
             Ash.get(Contract, contract_id, tenant: tenant, authorize?: false) do
        contract
        |> Ash.Changeset.for_update(:publish, %{},
          tenant: tenant,
          actor: actor,
          authorize?: false
        )
        |> Ash.update()
      end
    end

    notify_attendees(booking, :booked)
    {:ok, booking}
  end

  @impl true
  def on_updated(booking, _actor) do
    notify_attendees(booking, :updated)
    {:ok, booking}
  end

  @impl true
  def on_cancelled(booking, actor) do
    booking = Ash.load!(booking, [:resource], authorize?: false)
    tenant = Map.get(booking.__metadata__, :tenant)
    contract_id = extract_contract_id(booking.resource)

    if contract_id do
      with {:ok, %Contract{status: :pending_signature} = contract} <-
             Ash.get(Contract, contract_id, tenant: tenant, authorize?: false) do
        contract
        |> Ash.Changeset.for_update(:update, %{status: :draft},
          tenant: tenant,
          actor: actor,
          authorize?: false
        )
        |> Ash.update()
      end
    end

    notify_attendees(booking, :cancelled)
    {:ok, booking}
  end

  defp fetch_contract_id(nil, _tenant), do: nil

  defp fetch_contract_id(resource_id, tenant) do
    with {:ok, resource} <- Ash.get(Resource, resource_id, tenant: tenant, authorize?: false) do
      extract_contract_id(resource)
    else
      _ -> nil
    end
  end

  defp extract_contract_id(nil), do: nil

  defp extract_contract_id(resource) do
    metadata = resource.metadata || %{}
    Map.get(metadata, "contract_id") || Map.get(metadata, :contract_id)
  end
end
