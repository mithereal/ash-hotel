defmodule AshPhoenixStarter.Changes.CreateBookingResourceForHotelUnit do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    tenant = changeset.tenant

    Ash.Changeset.after_action(changeset, fn _changeset, unit ->
      attributes = %{
        name: "Hotel Room: #{unit.name}",
        type: :hotel_room,
        description: "Automatically created schedulable resource for hotel property unit.",
        active: true,
        property_unit_id: unit.id,
        metadata: %{property_unit_id: unit.id}
      }

      AshPhoenixStarter.Bookings.Resource
      |> Ash.Changeset.for_create(:create, attributes)
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create(tenant: tenant)

      {:ok, unit}
    end)
  end
end
