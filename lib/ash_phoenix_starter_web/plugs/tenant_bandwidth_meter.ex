defmodule AshPhoenixStarterWeb.Plugs.TenantBandwidthMeter do
  @moduledoc """
  Measures dynamic HTTP response bytes per hotel (`organization_id`) and region (`region_id`)
  and feeds them into `UsageTracker`.
  """
  import Plug.Conn
  alias AshPhoenixStarter.Billing.UsageTracker

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, fn conn ->
      with org_id when not is_nil(org_id) <- resolve_org_id(conn) do
        region_id = resolve_region_id(conn)
        response_bytes = calculate_response_bytes(conn)

        UsageTracker.record_usage(region_id, org_id, :bandwidth, response_bytes)
      end

      conn
    end)
  end

  # Adjust these keys to match how your router/auth assigns the active hotel & region
  defp resolve_org_id(conn) do
    conn.assigns[:current_organization_id] ||
      get_in(conn.assigns, [:current_organization, Access.key(:id)]) ||
      conn.private[:organization_id]
  end

  defp resolve_region_id(conn) do
    conn.assigns[:current_region_id] ||
      get_in(conn.assigns, [:current_region, Access.key(:id)]) ||
      conn.private[:region_id] ||
      "global"
  end

  defp calculate_response_bytes(conn) do
    body_bytes =
      case conn.resp_body do
        nil -> 0
        body when is_binary(body) -> byte_size(body)
        body when is_list(body) -> IO.iodata_length(body)
        _ -> 0
      end

    # Add ~400 bytes overhead for HTTP headers + TLS framing
    body_bytes + 400
  end
end
