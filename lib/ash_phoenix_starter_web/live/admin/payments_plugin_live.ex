defmodule HotelWeb.Admin.PaymentPluginsLive do
  use HotelWeb, :live_view

  alias Hotel.Payments.{Plugin, Registry}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Payment Provider Plugins")
      |> assign(:providers, Registry.list())
      |> allow_upload(:plugin_bundle,
        accept: ~w(.json),
        max_entries: 1,
        max_file_size: 2_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("install_plugin", _params, socket) do
    actor = socket.assigns.current_user

    results =
      consume_uploaded_entries(socket, :plugin_bundle, fn %{path: path}, _entry ->
        result = install_from_bundle_file(path, actor)
        {:ok, result}
      end)

    case results do
      [{:ok, plugin}] ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Installed #{plugin.runtime} plugin '#{plugin.provider_id}' across cluster."
         )
         |> assign(:providers, Registry.list())}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "Plugin installation failed: #{reason}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Please select a signed .plugin.json file.")}
    end
  end

  defp install_from_bundle_file(path, actor) do
    with {:ok, raw_json} <- File.read(path),
         {:ok, bundle} <- Jason.decode(raw_json),
         {:ok, runtime} <- parse_runtime(bundle["runtime"]),
         {:ok, code_payload} <- Base.decode64(bundle["payload_base64"] || ""),
         sig_b64 when is_binary(sig_b64) <- bundle["signature_b64"] do
      Plugin
      |> Ash.Changeset.for_create(
        :install_signed,
        %{
          runtime: runtime,
          module_name: bundle["module_name"],
          code_payload: code_payload,
          signature_b64: sig_b64,
          version: bundle["version"] || "1.0.0"
        },
        actor: actor
      )
      |> Ash.create()
      |> case do
        {:ok, plugin} -> {:ok, plugin}
        {:error, ash_err} -> {:error, Exception.message(ash_err)}
      end
    else
      _ -> {:error, "Malformed or unsigned .plugin.json bundle"}
    end
  end

  defp parse_runtime("beam"), do: {:ok, :beam}
  defp parse_runtime("lua"), do: {:ok, :lua}
  defp parse_runtime(_), do: {:error, :unsupported_runtime}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-10 px-4">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Payment Provider Plugins</h1>
        <p class="text-sm text-gray-600 mt-1">
          Upload Ed25519-signed BEAM (.beam) or Lua (.lua) payment provider bundles. Installed plugins hot-load immediately across all nodes.
        </p>
      </div>

      <div class="bg-white border rounded-xl p-6 mb-8 shadow-sm">
        <h2 class="text-lg font-semibold mb-4">Install Signed Provider Bundle</h2>

        <form
          id="plugin-upload-form"
          phx-submit="install_plugin"
          phx-change="validate"
          class="space-y-4"
        >
          <div class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center">
            <.live_file_input
              upload={@uploads.plugin_bundle}
              class="block mx-auto text-sm text-gray-700"
            />
            <p class="text-xs text-gray-500 mt-2">
              Accepts signed <code>.plugin.json</code> files up to 2MB
            </p>
          </div>

          <%= for entry <- @uploads.plugin_bundle.entries do %>
            <div class="flex items-center justify-between bg-gray-50 px-4 py-2 rounded border text-sm">
              <span class="font-medium">{entry.client_name}</span>
              <span class="text-gray-500">{entry.progress}%</span>
            </div>
          <% end %>

          <button
            type="submit"
            disabled={@uploads.plugin_bundle.entries == []}
            class="px-4 py-2 bg-indigo-600 text-white text-sm font-semibold rounded-lg hover:bg-indigo-700 disabled:opacity-50"
          >
            Verify &amp; Hot-Load Plugin
          </button>
        </form>
      </div>

      <div class="bg-white border rounded-xl shadow-sm overflow-hidden">
        <div class="px-6 py-4 border-b">
          <h2 class="text-lg font-semibold">Active Node Registry ({length(@providers)})</h2>
        </div>

        <table class="min-w-full divide-y divide-gray-200 text-sm">
          <thead class="bg-gray-50 text-left text-xs font-semibold text-gray-500 uppercase">
            <tr>
              <th class="px-6 py-3">Provider ID</th>
              <th class="px-6 py-3">Display Name</th>
              <th class="px-6 py-3">Runtime</th>
              <th class="px-6 py-3">Regions</th>
              <th class="px-6 py-3">Currencies</th>
              <th class="px-6 py-3">Pre-Auth Holds</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <%= for provider <- @providers do %>
              <tr>
                <td class="px-6 py-4 font-mono text-xs text-gray-800">{provider.id}</td>
                <td class="px-6 py-4 font-medium text-gray-900">{provider.name}</td>
                <td class="px-6 py-4">
                  <span class={[
                    "px-2 py-0.5 rounded text-xs font-semibold uppercase",
                    if(provider.runtime == :lua,
                      do: "bg-amber-100 text-amber-800",
                      else: "bg-indigo-100 text-indigo-800"
                    )
                  ]}>
                    {provider.runtime}
                  </span>
                </td>
                <td class="px-6 py-4 text-gray-600">{Enum.join(provider.regions, ", ")}</td>
                <td class="px-6 py-4 text-gray-600">{Enum.join(provider.currencies, ", ")}</td>
                <td class="px-6 py-4">
                  <%= if provider.supports_holds? do %>
                    <span class="text-emerald-600 font-semibold">Supported</span>
                  <% else %>
                    <span class="text-gray-400">Capture Only</span>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
