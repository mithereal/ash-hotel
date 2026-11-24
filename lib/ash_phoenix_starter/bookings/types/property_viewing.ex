defmodule AshPhoenixStarter.Bookings.Types.PropertyViewingHandler do
  @moduledoc """
  Handles prospective tenant/buyer property tours (:property_viewing).
  Blocks tours if the unit currently has an active, checked-in hotel stay or occupied status.
  """
  use AshPhoenixStarter.Bookings.BookingHandler

  alias AshPhoenixStarter.Bookings.Resource
  alias AshPhoenixStarter.Properties.Unit

  @impl true
  def validate_custom_rules(changeset, _actor) do
    tenant = changeset.tenant
    resource_id = Ash.Changeset.get_attribute(changeset, :resource_id)

    with {:ok, resource} <- Ash.get(Resource, resource_id, tenant: tenant, authorize?: false),
         unit_id when not is_nil(unit_id) <-
           resource.property_unit_id || get_in(resource.metadata || %{}, ["property_unit_id"]),
         {:ok, %Unit{status: :occupied}} <-
           Ash.get(Unit, unit_id, tenant: tenant, authorize?: false) do
      Ash.Changeset.add_error(
        changeset,
        field: :resource_id,
        message: "Cannot schedule a viewing while this unit is actively occupied."
      )
    else
      _ -> changeset
    end
  end
end
