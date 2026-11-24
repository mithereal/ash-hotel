defmodule AshPhoenixStarter.Changes.CreateBookingResourceForContract do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    tenant = changeset.tenant

    Ash.Changeset.after_action(changeset, fn _changeset, contract ->
      title = Map.get(contract, :title) || contract.id

      attributes = %{
        name: "Contract Consultation: #{title}",
        type: :contract_signing,
        description:
          "Automatically created scheduling resource for contract execution and review.",
        active: true,
        metadata: %{
          "contract_id" => contract.id,
          "property_id" => Map.get(contract, :property_id),
          "property_unit_id" => Map.get(contract, :property_unit_id)
        }
      }

      result =
        AshPhoenixStarter.Bookings.Resource
        |> Ash.Changeset.for_create(:create, attributes)
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.create(tenant: tenant)

      case result do
        {:ok, _resource} ->
          {:ok, contract}

        {:error, error} ->
          require Logger
          Logger.error("Failed to create contract booking resource: #{inspect(error)}")
          {:error, error}
      end
    end)
  end
end
