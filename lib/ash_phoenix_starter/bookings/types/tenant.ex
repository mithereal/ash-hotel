defmodule AshPhoenixStarter.Bookings.Types.TenantHandler do
  @moduledoc """
  Handles tenant onboarding, key handoffs, and move-in/move-out inspections (:tenant_onboarding, :move_out_inspection).
  """
  use AshPhoenixStarter.Bookings.BookingHandler

  alias AshPhoenixStarter.Bookings.Resource

  @impl true
  def validate_custom_rules(changeset, _actor) do
    tenant = changeset.tenant
    resource_id = Ash.Changeset.get_attribute(changeset, :resource_id)

    valid? =
      with {:ok, resource} <- Ash.get(Resource, resource_id, tenant: tenant, authorize?: false) do
        meta = resource.metadata || %{}

        not is_nil(
          resource.property_unit_id || Map.get(meta, "property_unit_id") ||
            Map.get(meta, :property_unit_id)
        )
      else
        _ -> false
      end

    if valid? do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :resource_id,
        message: "Tenant onboarding/inspection must be tied to a unit."
      )
    end
  end
end
