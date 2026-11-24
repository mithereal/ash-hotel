defmodule AshPhoenixStarterWeb.Admin.Features.Index do
  use AshPhoenixStarterWeb, :live_view

  on_mount {AshPhoenixStarterWeb.LiveUserAuth, :live_user_required}

  alias AshPhoenixStarter.Core.Feature

  import Ash.Query

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns[:current_user].organization.domain

    {:ok,
     socket
     |> assign(
       search_query: "",
       page: 1,
       page_size: @page_size,
       page_title: "Admin - Features Directory",
       tenant: tenant,
       feature: nil,
       form: nil,
       show_modal: false,
       show_file_picker_modal: false,
       primary_image: nil
     )
     |> load_features()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = parse_page(params["page"])

    socket =
      socket
      |> assign(page: page)
      |> load_features()

    {:noreply, socket}
  end

  defp parse_page(nil), do: 1

  defp parse_page(page_str) do
    case Integer.parse(page_str) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp load_features(socket) do
    tenant = socket.assigns.tenant
    page = socket.assigns.page
    limit = socket.assigns.page_size
    offset = (page - 1) * limit
    search_query = String.trim(socket.assigns.search_query)

    query =
      Feature
      |> Ash.Query.for_read(:read, %{}, tenant: tenant)
      |> Ash.Query.sort(name: :asc)

    query =
      if search_query == "" do
        query
      else
        pattern = "%#{search_query}%"
        Ash.Query.filter(query, fragment("? ILIKE ?", name, ^pattern))
      end

    query = Ash.Query.page(query, limit: limit, offset: offset, count: true)
    page_results = Ash.read!(query, tenant: tenant)

    assign(socket,
      features: page_results.results,
      total_count: page_results.count,
      total_pages: max(ceil(page_results.count / limit), 1)
    )
  end

  @impl true
  def handle_event("open_new", _, socket) do
    tenant = socket.assigns.tenant

    form =
      AshPhoenix.Form.for_create(Feature, :create,
        as: "feature",
        tenant: tenant
      )

    {:noreply,
     assign(socket,
       form: to_form(form),
       feature: nil,
       show_modal: true,
       show_file_picker_modal: false,
       primary_image: nil,
       page_title: "Add New Feature"
     )}
  end

  def handle_event("open_edit", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    feature = Ash.get!(Feature, id, tenant: tenant, load: [:primary_image])
    form = AshPhoenix.Form.for_update(feature, :update, as: "feature", tenant: tenant)

    {:noreply,
     assign(socket,
       form: to_form(form),
       feature: feature,
       show_modal: true,
       show_file_picker_modal: false,
       primary_image: feature.primary_image,
       page_title: "Edit Feature"
     )}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply,
     assign(socket,
       show_modal: false,
       form: nil,
       feature: nil,
       show_file_picker_modal: false,
       primary_image: nil
     )}
  end

  def handle_event("open_file_picker_modal", _, socket) do
    {:noreply, assign(socket, show_file_picker_modal: true)}
  end

  def handle_event("close_file_picker_modal", _, socket) do
    {:noreply, assign(socket, show_file_picker_modal: false)}
  end

  @impl true
  def handle_info({:file_selected, file}, socket) do
    {:noreply,
     socket
     |> assign(
       primary_image: file,
       show_file_picker_modal: false
     )}
  end

  def handle_info({:image_selected, file}, socket) do
    {:noreply,
     socket
     |> assign(
       primary_image: file,
       show_file_picker_modal: false
     )}
  end

  def handle_info({:selected, file}, socket) do
    {:noreply,
     socket
     |> assign(
       primary_image: file,
       show_file_picker_modal: false
     )}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    feature = Ash.get!(Feature, id, tenant: tenant)

    case Ash.destroy(feature, tenant: tenant, authorize?: false) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Feature deleted successfully.")
         |> assign(
           show_modal: false,
           form: nil,
           feature: nil,
           show_file_picker_modal: false,
           primary_image: nil
         )
         |> load_features()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to delete feature.")}
    end
  end

  def handle_event("toggle_feature_status", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    feature = Ash.get!(Feature, id, tenant: tenant)
    new_status = if feature.status == :active, do: :inactive, else: :active

    case feature
         |> Ash.Changeset.for_update(:update, %{status: new_status}, authorize?: false)
         |> Ash.update(tenant: tenant) do
      {:ok, _updated_feature} ->
        {:noreply,
         socket
         |> put_flash(:info, "Feature status changed to #{new_status}.")
         |> load_features()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to update feature status.")}
    end
  end

  def handle_event("search", %{"search_query" => query}, socket) do
    {:noreply,
     socket
     |> assign(search_query: query, page: 1)
     |> load_features()}
  end

  def handle_event("change_page", %{"page" => page_str}, socket) do
    page = parse_page(page_str)

    {:noreply,
     socket
     |> assign(page: page)
     |> load_features()
     |> push_patch(to: ~p"/admin/features?page=#{page}")}
  end

  @impl true
  def handle_event("validate", %{"feature" => feature_params}, socket) do
    feature_params =
      if socket.assigns.primary_image do
        Map.put(feature_params, "primary_image_id", socket.assigns.primary_image.id)
      else
        feature_params
      end

    form =
      socket.assigns.form
      |> AshPhoenix.Form.validate(feature_params)

    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("save", %{"feature" => feature_params}, socket) do
    feature_params =
      if socket.assigns.primary_image do
        Map.put(feature_params, "primary_image_id", socket.assigns.primary_image.id)
      else
        feature_params
      end

    case AshPhoenix.Form.submit(socket.assigns.form, params: feature_params) do
      {:ok, _feature} ->
        {:noreply,
         socket
         |> put_flash(:info, "Feature saved successfully.")
         |> assign(
           show_modal: false,
           form: nil,
           feature: nil,
           show_file_picker_modal: false,
           primary_image: nil
         )
         |> load_features()}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} uri={@uri}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 text-white bg-transparent">
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
          <div>
            <h1 class="text-2xl font-bold text-white">Admin Features Management</h1>
            <p class="text-sm text-gray-400 mt-1">
              Review, update, or inspect all features across the system.
            </p>
          </div>
          <.button
            phx-click="open_new"
            class="bg-black text-white border border-neutral-800 px-4 py-2 rounded-lg text-sm font-medium hover:bg-neutral-900 transition-colors cursor-pointer"
          >
            + Add New Feature
          </.button>
        </div>

        <div class="mb-6 max-w-md">
          <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
            Filter Features
          </label>
          <form phx-change="search" phx-submit="search">
            <input
              type="text"
              name="search_query"
              value={@search_query}
              placeholder="Filter by feature name..."
              phx-debounce="150"
              autocomplete="off"
              class="w-full rounded-lg bg-black border border-neutral-800 px-4 py-2 text-white text-sm shadow-sm focus:ring-white focus:border-white placeholder-gray-500"
            />
          </form>
        </div>

        <div class="bg-transparent shadow-sm ring-1 ring-neutral-800 sm:rounded-xl overflow-hidden">
          <table class="min-w-full divide-y divide-neutral-800">
            <thead class="bg-black/40">
              <tr>
                <th
                  scope="col"
                  class="py-3.5 pl-4 pr-3 text-left text-xs font-semibold text-white sm:pl-6"
                >
                  Feature Name
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Category
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Status
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Description
                </th>
                <th
                  scope="col"
                  class="relative py-3.5 pl-3 pr-4 sm:pr-6 text-right text-xs font-semibold text-white"
                >
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-neutral-800 bg-transparent">
              <%= for feature <- @features do %>
                <tr class="hover:bg-neutral-900/40 transition-colors">
                  <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-white sm:pl-6">
                    {feature.name}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-400 uppercase">
                    {feature.category}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm">
                    <button
                      phx-click="toggle_feature_status"
                      phx-value-id={feature.id}
                      class={[
                        "px-2.5 py-1 rounded-full text-xs font-semibold border transition-colors cursor-pointer",
                        feature.status == :active &&
                          "bg-green-900/50 text-green-400 border-green-800 hover:bg-green-900/80",
                        feature.status == :inactive &&
                          "bg-neutral-800 text-gray-400 border-neutral-700 hover:bg-neutral-700"
                      ]}
                      title="Click to toggle status"
                    >
                      {feature.status}
                    </button>
                  </td>
                  <td class="px-3 py-4 text-sm text-gray-400 max-w-xs truncate">
                    {feature.description}
                  </td>
                  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6 space-x-2">
                    <.button
                      phx-click="open_edit"
                      phx-value-id={feature.id}
                      class="text-white hover:text-gray-300 bg-black hover:bg-neutral-900 border border-neutral-800 px-3 py-1.5 rounded-md text-xs font-medium transition-colors cursor-pointer"
                    >
                      Edit
                    </.button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>

          <div class="flex items-center justify-between px-4 py-3 bg-black/40 border-t border-neutral-800 sm:px-6">
            <div class="flex space-x-2">
              <%= if @page > 1 do %>
                <.button
                  phx-click="change_page"
                  phx-value-page={@page - 1}
                  class="px-3 py-1.5 bg-black border border-neutral-800 rounded-md text-xs font-medium text-white hover:bg-neutral-900 cursor-pointer"
                >
                  Previous
                </.button>
              <% end %>
              <%= if @page < @total_pages do %>
                <.button
                  phx-click="change_page"
                  phx-value-page={@page + 1}
                  class="px-3 py-1.5 bg-black border border-neutral-800 rounded-md text-xs font-medium text-white hover:bg-neutral-900 cursor-pointer"
                >
                  Next
                </.button>
              <% end %>
            </div>
            <div class="text-sm text-gray-400">
              Showing page <span class="font-medium text-white">{@page}</span>
              of <span class="font-medium text-white">{@total_pages}</span>
              (<span class="font-medium text-white">{@total_count}</span> total results)
            </div>
          </div>
        </div>
      </div>
      
    <!-- MAIN FEATURE MODAL -->
      <%= if @show_modal and @form do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md">
          <div class="bg-black text-white rounded-2xl shadow-2xl w-full max-w-lg overflow-hidden border border-neutral-800">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-black">
              <h3 class="text-lg font-semibold text-white">
                {if @feature, do: "Edit Feature", else: "Add New Feature"}
              </h3>
              <.button
                phx-click="close_modal"
                class="text-gray-400 hover:text-white text-sm font-medium cursor-pointer"
              >
                ✕
              </.button>
            </div>

            <.form
              for={@form}
              id="feature-form"
              phx-change="validate"
              phx-submit="save"
              class="p-6 space-y-6 max-h-[80vh] overflow-y-auto bg-black text-white"
            >
              <input
                type="hidden"
                name="feature[primary_image_id]"
                value={@primary_image && @primary_image.id}
              />

              <div>
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                  Feature Name
                </label>
                <.input
                  field={@form[:name]}
                  type="text"
                  placeholder="High-speed Wi-Fi"
                  class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                />
              </div>

              <div>
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                  Category
                </label>
                <.input
                  field={@form[:category]}
                  type="select"
                  options={[
                    {"System", :system},
                    {"Amenity", :amenity},
                    {"Exterior", :exterior},
                    {"Utility", :utility},
                    {"Security", :security}
                  ]}
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
                  placeholder="Details about this feature..."
                  class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                />
              </div>
              
    <!-- Primary Image Trigger Section -->
              <div class="flex flex-col items-center justify-center pt-2">
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-2 text-center">
                  Primary Image
                </label>
                <div class="flex flex-col items-center justify-center">
                  <.button
                    phx-click="open_file_picker_modal"
                    class="relative w-24 h-24 rounded-lg border border-neutral-700 bg-neutral-900 hover:border-white flex flex-col items-center justify-center overflow-hidden transition-colors cursor-pointer shadow-sm"
                  >
                    <%= if @primary_image do %>
                      <img
                        src={@primary_image.file_url}
                        alt="Primary"
                        class="w-full h-full object-cover"
                      />
                    <% else %>
                      <span class="text-2xl text-gray-400">+</span>
                      <span class="text-[10px] text-gray-400 uppercase mt-1">Select</span>
                    <% end %>
                  </.button>
                </div>
              </div>

              <div class="flex items-center justify-between pt-4 border-t border-neutral-800">
                <div>
                  <%= if @feature do %>
                    <.button
                      phx-click="delete"
                      phx-value-id={@feature.id}
                      class="px-4 py-2 border border-red-900/50 bg-red-950/30 text-red-400 rounded-lg text-sm font-medium hover:bg-red-900/40 cursor-pointer"
                    >
                      Delete Feature
                    </.button>
                  <% end %>
                </div>
                <div class="flex space-x-3">
                  <.button
                    phx-click="close_modal"
                    class="px-4 py-2 border border-neutral-800 rounded-lg text-sm font-medium text-white hover:bg-neutral-900 cursor-pointer"
                  >
                    Cancel
                  </.button>
                  <.button
                    type="submit"
                    phx-disable-with="Saving..."
                    class="px-4 py-2 bg-white text-black rounded-lg text-sm font-medium hover:bg-gray-200 shadow-sm cursor-pointer"
                  >
                    Save Feature
                  </.button>
                </div>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
      
    <!-- SEPARATE FILE PICKER DIALOG MODAL -->
      <%= if @show_file_picker_modal do %>
        <div class="fixed inset-0 z-[60] flex items-center justify-center bg-black/85 backdrop-blur-md p-4">
          <div class="bg-neutral-950 text-white rounded-2xl shadow-2xl w-full max-w-3xl overflow-hidden border border-neutral-800 flex flex-col max-h-[85vh]">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-black">
              <h3 class="text-base font-semibold uppercase text-gray-200">
                Select Primary Image
              </h3>
              <.button
                phx-click="close_file_picker_modal"
                class="text-gray-400 hover:text-white text-sm font-medium cursor-pointer"
              >
                ✕ Close
              </.button>
            </div>
            <div class="p-6 overflow-y-auto flex-1 space-y-6">
              <div class="bg-black/40 border border-neutral-800 rounded-xl p-4 sm:p-6">
                <h4 class="text-xs font-semibold text-gray-400 uppercase mb-3">Available Images</h4>
                <div class="">
                  <.live_component
                    module={AshPhoenixStarterWeb.Components.FilePickerGridComponent}
                    id="feature-file-picker"
                    organization_id={@current_user.organization.id}
                    tenant={@tenant}
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
