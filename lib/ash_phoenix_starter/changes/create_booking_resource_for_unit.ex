defmodule AshPhoenixStarter.Changes.CreateBookingResourceForUnit do
  use Ash.Resource.Change

  @hotel_unit_types [:hotel_room, :suite, :penthouse]

  def change(changeset, _opts, _context) do
    tenant = changeset.tenant

    Ash.Changeset.after_action(changeset, fn _changeset, unit ->
      resource_specs = build_resource_specs(unit)

      Enum.reduce_while(resource_specs, {:ok, unit}, fn attrs, {:ok, acc_unit} ->
        result =
          AshPhoenixStarter.Bookings.Resource
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.Changeset.set_tenant(tenant)
          |> Ash.create(tenant: tenant)

        case result do
          {:ok, _resource} ->
            {:cont, {:ok, acc_unit}}

          {:error, error} ->
            require Logger
            Logger.error("Failed to create unit booking resource: #{inspect(error)}")
            {:halt, {:error, error}}
        end
      end)
    end)
  end

  defp build_resource_specs(unit) do
    base_metadata = %{
      "property_unit_id" => unit.id,
      "property_id" => unit.property_id,
      "unit_type" => to_string(unit.unit_type)
    }

    viewing_resource = %{
      name: "#{unit.unit_number} - #{unit.name} (Viewing)",
      type: :property_viewing,
      description: "Property viewing booking resource for #{unit.name}",
      active: unit.active,
      property_unit_id: unit.id,
      metadata: base_metadata
    }

    if unit.unit_type in @hotel_unit_types do
      hotel_resource = %{
        name: "#{unit.unit_number} - #{unit.name} (Stay)",
        type: :hotel_room,
        description: "Hotel room booking resource for #{unit.name}",
        active: unit.active,
        property_unit_id: unit.id,
        metadata: base_metadata
      }

      [viewing_resource, hotel_resource]
    else
      [viewing_resource]
    end
  end
end
