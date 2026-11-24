defmodule AshPhoenixStarterWeb.Live.Hooks.NotificationHook do
  import Phoenix.LiveView
  alias Phx.Live.Favicon

   def on_mount(:default, _params, _session, socket) do
    org_id = resolve_org_id(socket)
    region_id = socket.assigns[:current_region_id] || "global"

    if connected?(socket) and org_id do
      Phoenix.PubSub.subscribe(AshPhoenixStarter.PubSub, "notifications:org:#{org_id}")
    end

    socket =
      socket
      |> attach_hook(:favicon_notifier, :handle_info, fn
        {:new_notification, count}, socket ->
          {:halt, update_favicon_layout(socket, count)}

        {:quota_warning, percent_used}, socket ->

          {:plan_updated, _status}, socket ->
          socket =
            socket
            |> put_flash(:info, "Your subscription plan has been updated and your new bandwidth limits are active.")
            |> update_favicon_layout(0)

          {:halt, socket}

          socket =
            socket
            |> put_flash(:error, "Warning: Your property has used #{percent_used}% of its monthly bandwidth.")
            |> update_favicon_layout(1)

          {:halt, socket}

        _other_message, socket ->
          {:cont, socket}
      end)
      |> attach_hook(:liveview_bandwidth_meter, :handle_event, fn _event, params, socket ->
        if org_id do
          # Estimate WebSocket frame payload + diff overhead (~1.5 KB base + incoming params)
          estimated_bytes = :erlang.external_size(params) + 1_500
          AshPhoenixStarter.Billing.UsageTracker.record_usage(region_id, org_id, :bandwidth, estimated_bytes)
        end

        {:cont, socket}
      end)

    {:cont, socket}
  end


  defp resolve_org_id(socket) do
    socket.assigns[:current_organization_id] ||
      get_in(socket.assigns, [:current_organization, Access.key(:id)])
  end

  defp update_favicon_layout(socket, count) do
    if count > 0 do
      svg_template =
        "data:image/svg+xml,<svg xmlns='http://w3.org' viewBox='0 0 100 100'><circle cx='50' cy='50' r='50' fill='{counter_background}' /><text x='50%' y='50%' text-anchor='middle' dominant-baseline='central' font-size='55' fill='white'>{counter}</text></svg>"

      Favicon.set_dynamic("favicon-32", "subfolder", "blank")
      Favicon.set_dynamic("favicon-16", "subfolder", "blank")
      Favicon.set_dynamic("dynamic-svg-favicon", "dynamic-href", svg_template)
      Favicon.set_dynamic("dynamic-svg-favicon", "counter", count)
      Favicon.set_dynamic("dynamic-svg-favicon", "counter_background", "red")
    else
      current_page_folder =
        socket.view
        |> Module.split()
        |> List.last()
        |> String.replace("Live", "")
        |> String.downcase()

      Favicon.set_dynamic("dynamic-svg-favicon", "dynamic-href", "")
      Favicon.set_dynamic("favicon-32", "subfolder", current_page_folder)
      Favicon.set_dynamic("favicon-16", "subfolder", current_page_folder)
    end
  end
end
