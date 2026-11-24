defmodule AshPhoenixStarter.Changes.CreateBookingResourceForProperty do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    tenant = changeset.tenant

    Ash.Changeset.after_action(changeset, fn _changeset, property ->
      attributes = %{
        name: property.name,
        type: :property_viewing,
        description: "Automatically created booking resource for property: #{property.name}",
        active: true,
        metadata: %{
          "property_id" => property.id,
          "resource_type" => "property",
          "resource_id" => property.id
        }
      }

      result =
        AshPhoenixStarter.Bookings.Resource
        |> Ash.Changeset.for_create(:create, attributes)
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.create(tenant: tenant)

      case result do
        {:ok, _resource} ->
          {:ok, property}

        {:error, error} ->
          require Logger
          Logger.error("Failed to create property booking resource: #{inspect(error)}")
          {:error, error}
      end
    end)
  end
end
