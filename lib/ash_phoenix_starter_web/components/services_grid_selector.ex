defmodule AshPhoenixStarterWeb.Components.ServicePickerGridComponent do
  use AshPhoenixStarterWeb, :live_component

  alias AshPhoenixStarter.Core.Service

  import Ash.Query

  @page_size 12

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       services: [],
       page: 1,
       total_pages: 1,
       more_results?: false,
       search_query: "",
       selected_ids: MapSet.new(),
       show_create_modal: false,
       organization_id: nil,
       form: nil
     )
     |> allow_upload(:primary_image,
       # keep this in sync with ImageUploader.validate/1 -- it only
       # accepts jpg/jpeg/png/webp (no gif), so a .gif would pass this
       # client-side check and then fail silently server-side.
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 8_000_000
     )}
  end

  @impl true
  def update(assigns, socket) do
    # Never let the parent's assigns clobber in-progress picks / paging state.
    incoming = Map.drop(assigns, [:selected_ids, :page, :search_query])
    socket = assign(socket, incoming)

    # Seed the selection from the parent only when explicitly asked to.
    socket =
      if assigns[:reset_selection] do
        assign(socket, selected_ids: MapSet.new(assigns[:selected_ids] || []), page: 1)
      else
        socket
      end

    {:ok, load_services(socket)}
  end

  defp load_services(socket) do
    tenant = socket.assigns[:tenant]
    limit = socket.assigns[:limit] || @page_size
    page = socket.assigns[:page] || 1
    offset = (page - 1) * limit
    search = String.trim(socket.assigns[:search_query] || "")

    query =
      Service
      |> Ash.Query.for_read(:read, %{}, tenant: tenant, domain: AshPhoenixStarter.Core)
      |> Ash.Query.load([:primary_image])
      |> Ash.Query.sort(name: :asc)

    # Autocomplete-style name matching; empty search shows everything.
    query =
      if search == "" do
        query
      else
        Ash.Query.filter(query, contains(fragment("lower(?)", name), ^String.downcase(search)))
      end

    # The :read action declares `pagination offset?: true`, so paging MUST go
    # through the `page:` option. Using Ash.Query.limit/offset against a
    # paginated action is what made this return something the old `case` didn't
    # match, so it fell through to the catch-all and rendered an empty grid.
    # `count: true` is what actually populates `more?` and the total.
    case Ash.read(query, page: [limit: limit, offset: offset, count: true]) do
      {:ok, %Ash.Page.Offset{results: results, more?: more?, count: count}} ->
        total_pages = if is_integer(count) and count > 0, do: ceil(count / limit), else: 1
        assign(socket, services: results, more_results?: more?, total_pages: total_pages)

      {:ok, results} when is_list(results) ->
        assign(socket, services: results, more_results?: false, total_pages: 1)

      {:error, _error} ->
        assign(socket, services: [], more_results?: false, total_pages: 1)
    end
  end

  @impl true
  def handle_event("search", %{"search_query" => query}, socket) do
    # Reset to page 1 on every new term, otherwise you can sit on an
    # out-of-range page and see nothing.
    {:noreply,
     socket
     |> assign(search_query: query, page: 1)
     |> load_services()}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply,
     socket
     |> assign(search_query: "", page: 1)
     |> load_services()}
  end

  def handle_event("next_page", _, socket) do
    if socket.assigns.more_results? do
      {:noreply, socket |> assign(page: socket.assigns.page + 1) |> load_services()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prev_page", _, socket) do
    {:noreply,
     socket
     |> assign(page: max(1, socket.assigns.page - 1))
     |> load_services()}
  end

  # Toggle membership instead of firing straight up to the parent -- selection
  # is confirmed with the Select button.
  def handle_event("toggle_service", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, selected_ids: selected)}
  end

  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, selected_ids: MapSet.new())}
  end

  def handle_event("confirm_selection", _, socket) do
    tenant = socket.assigns[:tenant]
    ids = MapSet.to_list(socket.assigns.selected_ids)

    services =
      if ids == [] do
        []
      else
        Service
        |> Ash.Query.for_read(:read, %{}, tenant: tenant, domain: AshPhoenixStarter.Core)
        |> Ash.Query.load([:primary_image])
        |> Ash.Query.filter(id in ^ids)
        |> Ash.read!(page: false)
        |> unwrap_results()
      end

    send(self(), {:services_selected, services})
    {:noreply, socket}
  end

  def handle_event("open_create", _, socket) do
    form =
      Service
      |> AshPhoenix.Form.for_create(:create,
        as: "service",
        tenant: socket.assigns[:tenant],
        domain: AshPhoenixStarter.Core
      )

    {:noreply, assign(socket, show_create_modal: true, form: to_form(form))}
  end

  def handle_event("close_create", _, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.primary_image.entries, socket, fn entry, acc ->
        cancel_upload(acc, :primary_image, entry.ref)
      end)

    {:noreply, assign(socket, show_create_modal: false, form: nil)}
  end

  def handle_event("cancel_image_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :primary_image, ref)}
  end

  def handle_event("validate_create", %{"service" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("save_create", %{"service" => params}, socket) do
    organization_id = socket.assigns[:organization_id]
    # 1. Validate the form data against the changeset first
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    if form.source.valid? do
      # Turn whatever image was queued (if any) into a FileAsset first, so its
      # id can ride along with the rest of the create params.
      uploaded_asset =
        consume_uploaded_entries(socket, :primary_image, fn %{path: path}, entry ->
          scope = %{organization_id: organization_id, type: :service}

          plug_upload = %Plug.Upload{
            path: path,
            filename: entry.client_name,
            content_type: entry.client_type
          }

          case AshPhoenixStarter.Uploads.ImageUploader.store(plug_upload, scope) do
            {:ok, stored_filename} ->
              file_url = AshPhoenixStarter.Uploads.ImageUploader.url(stored_filename, scope)

              asset =
                AshPhoenixStarter.Core.FileAsset
                |> Ash.Changeset.for_create(:create, %{
                  file_url: file_url,
                  filename: entry.client_name,
                  organization_id: organization_id,
                  type: :service
                })
                |> Ash.create!()

              {:ok, asset}

            {:error, reason} ->
              raise "Image upload failed: #{inspect(reason)}"
          end
        end)
        |> List.first()

      params =
        if uploaded_asset do
          Map.put(params, "primary_image_id", uploaded_asset.id)
        else
          params
        end

      case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
        {:ok, service} ->
          # Auto-select the new service and refresh so it shows up in the grid
          # (load_services already loads :primary_image, so the thumbnail will
          # be correct as soon as the grid re-renders).
          {:noreply,
           socket
           |> assign(
             show_create_modal: false,
             form: nil,
             selected_ids: MapSet.put(socket.assigns.selected_ids, service.id)
           )
           |> load_services()}

        {:error, form} ->
          {:noreply, assign(socket, form: to_form(form))}
      end
    else
      # 3. If invalid, do not upload anything and render errors on the form
      {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp unwrap_results(%Ash.Page.Offset{results: results}), do: results
  defp unwrap_results(results) when is_list(results), do: results
  defp unwrap_results(_), do: []

  defp selected?(selected_ids, id), do: MapSet.member?(selected_ids, id)

  defp error_to_string(:too_large), do: "File is too large (max 8MB)."
  defp error_to_string(:too_many_files), do: "You can only upload one image."
  defp error_to_string(:not_accepted), do: "Unsupported file type."
  defp error_to_string(other), do: "Upload failed (#{other})."

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center gap-3">
        <h3 class="text-sm font-semibold text-gray-300 uppercase tracking-wider whitespace-nowrap">
          Available Services
        </h3>
        <button
          phx-click="open_create"
          phx-target={@myself}
          class="px-4 py-2 bg-white text-black rounded-lg text-sm font-medium hover:bg-gray-200 transition-colors cursor-pointer whitespace-nowrap"
        >
          + Create Service
        </button>
      </div>
      
    <!-- Autocomplete-style search over service names -->
      <form phx-change="search" phx-submit="search" phx-target={@myself} class="relative">
        <input
          type="text"
          name="search_query"
          value={@search_query}
          placeholder="Search services by name..."
          autocomplete="off"
          phx-debounce="300"
          class="w-full rounded-lg bg-black border border-neutral-800 text-white text-sm px-3 py-2 pr-16 focus:ring-white focus:border-white"
        />
        <%= if @search_query != "" do %>
          <button
            phx-click="clear_search"
            phx-target={@myself}
            class="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-gray-400 hover:text-white cursor-pointer"
          >
            Clear
          </button>
        <% end %>
      </form>

      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 max-h-[60vh] overflow-y-auto pr-1">
        <%= for service <- @services do %>
          <div
            class={[
              "group bg-neutral-900 rounded-xl p-3 flex flex-col justify-between transition-all cursor-pointer border-2",
              if(selected?(@selected_ids, service.id),
                do: "border-red-500 ring-2 ring-red-500/40",
                else: "border-neutral-800 hover:border-white"
              )
            ]}
            phx-click="toggle_service"
            phx-value-id={service.id}
            phx-target={@myself}
          >
            <!-- Image-forward tile -->
            <div class="relative w-full aspect-square rounded-lg bg-neutral-800 overflow-hidden mb-2 flex items-center justify-center">
              <%= if service.primary_image do %>
                <img
                  src={service.primary_image.file_url}
                  alt={service.name}
                  class="w-full h-full object-cover"
                />
              <% else %>
                <span class="text-xs text-gray-500 uppercase tracking-wide">No Image</span>
              <% end %>

              <%= if selected?(@selected_ids, service.id) do %>
                <span class="absolute top-1.5 right-1.5 bg-red-500 text-white text-[10px] font-bold rounded-full w-5 h-5 flex items-center justify-center shadow">
                  ✓
                </span>
              <% end %>
            </div>

            <div class="truncate">
              <h4 class="text-sm font-medium text-white truncate">{service.name}</h4>
              <p class="text-xs text-gray-400 truncate">{service.description || "No description"}</p>
            </div>
          </div>
        <% end %>

        <%= if @services == [] do %>
          <div class="col-span-full text-center py-10 text-sm text-gray-500">
            <%= if @search_query != "" do %>
              No services match "{@search_query}".
            <% else %>
              No services found.
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="flex justify-between items-center pt-2 border-t border-neutral-800">
        <button
          phx-click="prev_page"
          phx-target={@myself}
          disabled={@page <= 1}
          class="px-3 py-1.5 text-xs font-medium bg-neutral-900 border border-neutral-800 text-white rounded-lg disabled:opacity-40 disabled:cursor-not-allowed hover:bg-neutral-800 cursor-pointer"
        >
          ← Previous
        </button>
        <span class="text-xs text-gray-400">Page {@page} of {@total_pages}</span>
        <button
          phx-click="next_page"
          phx-target={@myself}
          disabled={!@more_results?}
          class="px-3 py-1.5 text-xs font-medium bg-neutral-900 border border-neutral-800 text-white rounded-lg disabled:opacity-40 disabled:cursor-not-allowed hover:bg-neutral-800 cursor-pointer"
        >
          Next →
        </button>
      </div>
      
    <!-- Confirm selection -->
      <div class="flex justify-between items-center gap-3 pt-3 border-t border-neutral-800">
        <span class="text-xs text-gray-400">{MapSet.size(@selected_ids)} selected</span>
        <div class="flex gap-2">
          <button
            phx-click="clear_selection"
            phx-target={@myself}
            disabled={MapSet.size(@selected_ids) == 0}
            class="px-4 py-2 border border-neutral-800 rounded-lg text-sm font-medium text-white hover:bg-neutral-900 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
          >
            Clear
          </button>
          <button
            phx-click="confirm_selection"
            phx-target={@myself}
            disabled={MapSet.size(@selected_ids) == 0}
            class="px-5 py-2 bg-red-600 text-white rounded-lg text-sm font-semibold hover:bg-red-500 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
          >
            Select
          </button>
        </div>
      </div>

      <%= if @show_create_modal do %>
        <div class="fixed inset-0 z-[80] flex items-center justify-center bg-black/90 backdrop-blur-md p-4">
          <div class="bg-black text-white rounded-2xl shadow-2xl w-full max-w-lg overflow-hidden border border-neutral-800">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-neutral-950">
              <h3 class="text-base font-semibold text-white">Create New Service</h3>
              <button
                phx-click="close_create"
                phx-target={@myself}
                class="text-gray-400 hover:text-white text-sm font-medium cursor-pointer"
              >
                ✕
              </button>
            </div>

            <.form
              for={@form}
              id="service-create-form"
              phx-change="validate_create"
              phx-submit="save_create"
              phx-target={@myself}
              class="p-6 space-y-4"
            >
              <div>
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                  Service Name
                </label>
                <.input
                  field={@form[:name]}
                  type="text"
                  placeholder="Service Name"
                  class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                />
              </div>

              <div>
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                  Description
                </label>
                <.input
                  field={@form[:description]}
                  type="textarea"
                  placeholder="Optional description..."
                  class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                />
              </div>

              <div>
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                  Default Price
                </label>
                <.input
                  field={@form[:default_price]}
                  type="number"
                  step="0.01"
                  placeholder="0.00"
                  class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                />
              </div>

              <div phx-drop-target={@uploads.primary_image.ref}>
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">Image</label>

                <%= if @uploads.primary_image.entries == [] do %>
                  <label
                    for={@uploads.primary_image.ref}
                    class="flex flex-col items-center justify-center gap-1 border-2 border-dashed border-neutral-700 hover:border-white rounded-xl py-6 cursor-pointer transition-colors"
                  >
                    <span class="text-xl text-gray-400">⇧</span>
                    <span class="text-xs text-gray-300">
                      Drag & drop an image, or click to browse
                    </span>
                    <span class="text-[10px] text-gray-500">JPG, PNG, WEBP or GIF, up to 8MB</span>
                  </label>
                <% end %>
                <.live_file_input upload={@uploads.primary_image} class="hidden" />

                <%= for entry <- @uploads.primary_image.entries do %>
                  <div class="flex items-center gap-3 bg-neutral-900 border border-neutral-800 rounded-lg p-3">
                    <.live_img_preview
                      entry={entry}
                      class="w-14 h-14 rounded-lg object-cover flex-shrink-0"
                    />
                    <div class="flex-1 min-w-0">
                      <p class="text-sm text-white truncate">{entry.client_name}</p>
                      <div class="w-full h-1.5 bg-neutral-800 rounded-full mt-1 overflow-hidden">
                        <div class="h-full bg-white" style={"width: #{entry.progress}%"}></div>
                      </div>
                    </div>
                    <button
                      phx-click="cancel_image_upload"
                      phx-value-ref={entry.ref}
                      phx-target={@myself}
                      class="text-gray-400 hover:text-red-400 text-sm cursor-pointer flex-shrink-0"
                    >
                      ✕
                    </button>
                  </div>

                  <%= for err <- upload_errors(@uploads.primary_image, entry) do %>
                    <p class="text-xs text-red-400 mt-1">{error_to_string(err)}</p>
                  <% end %>
                <% end %>
              </div>

              <div class="flex justify-end space-x-3 pt-4 border-t border-neutral-800">
                <button
                  phx-click="close_create"
                  phx-target={@myself}
                  class="px-4 py-2 border border-neutral-800 rounded-lg text-sm font-medium text-white hover:bg-neutral-900 cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  phx-disable-with="Creating..."
                  class="px-4 py-2 bg-white text-black rounded-lg text-sm font-medium hover:bg-gray-200 shadow-sm cursor-pointer"
                >
                  Save Service
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
