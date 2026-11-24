defmodule AshPhoenixStarter.Billing.TelemetryHandler do
  @moduledoc """
  Attaches to storage and Phoenix telemetry events and forwards byte counts
  to the Horde-supervised `UsageTracker` per hotel and region.
  """

  alias AshPhoenixStarter.Billing.UsageTracker

  @events [
    [:ash_phoenix_starter, :storage, :upload],
    [:ash_phoenix_starter, :storage, :delete],
    [:ash_phoenix_starter, :storage, :egress_estimate],
    [:ash_phoenix_starter, :storage, :tus_chunk_ingress]
  ]

  def attach do
    :telemetry.attach_many(
      "ash-phoenix-starter-billing-handler",
      @events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:ash_phoenix_starter, :storage, event], %{bytes: bytes}, meta, _config) do
    with org_id when not is_nil(org_id) <- Map.get(meta, :organization_id) do
      region_id = Map.get(meta, :region_id, "global")

      case event do
        :upload ->
          UsageTracker.record_usage(region_id, org_id, :storage, bytes)

        :delete ->
          UsageTracker.record_usage(region_id, org_id, :storage, bytes)

        :tus_chunk_ingress ->
          UsageTracker.record_usage(region_id, org_id, :storage, bytes)
          UsageTracker.record_usage(region_id, org_id, :bandwidth, bytes)

        :egress_estimate ->
          UsageTracker.record_usage(region_id, org_id, :bandwidth, bytes)
      end
    end
  end
end
