defmodule AshPhoenixStarterWeb.Admin.Properties.Index do
  use AshPhoenixStarterWeb, :live_view

  alias AshPhoenixStarter.Properties.Property
  alias AshPhoenixStarter.Core.Market
  alias AshPhoenixStarter.Ledgers.Account

  import Ash.Query

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns[:current_user].organization.domain

    markets =
      Market
      |> Ash.Query.for_read(:list_all, %{}, tenant: tenant)
      |> Ash.read!()
      |> Enum.map(&{&1.name, &1.id})

    {:ok,
     socket
     |> assign(
       markets: markets,
       search_query: "",
       page: 1,
       page_size: @page_size,
       page_title: "Admin - Properties Directory",
       tenant: tenant,
       property: nil,
       form: nil,
       modal_type: nil,
       modal_tab: :details,
       accounts: [],
       property_images: [],
       property_features: [],
       property_services: [],
       primary_image_id: nil,
       picker_mode: nil,
       show_file_picker_modal: false,
       show_service_picker_modal: false,
       show_feature_picker_modal: false
     )
     |> load_supporting_data()
     |> load_properties()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = parse_page(params["page"])

    socket =
      socket
      |> assign(page: page)
      |> load_properties()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:file_selected, file}, socket) do
    current_images = socket.assigns.property_images
    picker_mode = socket.assigns.picker_mode

    {updated_images, primary_id} =
      case picker_mode do
        "primary" ->
          new_imgs =
            if Enum.any?(current_images, &(&1.id == file.id)),
              do: current_images,
              else: current_images ++ [file]

          {new_imgs, file.id}

        _ ->
          new_imgs =
            if Enum.any?(current_images, &(&1.id == file.id)),
              do: current_images,
              else: current_images ++ [file]

          p_id =
            socket.assigns.primary_image_id ||
              if length(current_images) == 0, do: file.id, else: socket.assigns.primary_image_id

          {new_imgs, p_id}
      end

    current_params =
      if socket.assigns.form, do: socket.assigns.form.params, else: %{}

    updated_params = Map.put(current_params, "primary_image_id", primary_id)

    updated_form =
      if socket.assigns.form do
        AshPhoenix.Form.validate(socket.assigns.form, updated_params)
      else
        socket.assigns.form
      end

    {:noreply,
     socket
     |> assign(
       property_images: updated_images,
       primary_image_id: primary_id,
       form: if(updated_form, do: to_form(updated_form), else: nil),
       show_file_picker_modal: false,
       picker_mode: nil
     )}
  end

  def handle_info({:services_selected, services}, socket) when is_list(services) do
    current_services = socket.assigns.property_services
    updated_services = Enum.uniq_by(current_services ++ services, & &1.id)

    {:noreply,
     socket
     |> assign(
       property_services: updated_services,
       show_service_picker_modal: false
     )}
  end

  def handle_info({:service_selected, service}, socket) do
    current_services = socket.assigns.property_services

    updated_services =
      if Enum.any?(current_services, &(&1.id == service.id)),
        do: current_services,
        else: current_services ++ [service]

    {:noreply,
     socket
     |> assign(
       property_services: updated_services,
       show_service_picker_modal: false
     )}
  end

  def handle_info({:features_selected, features}, socket) when is_list(features) do
    current_features = socket.assigns.property_features
    updated_features = Enum.uniq_by(current_features ++ features, & &1.id)

    {:noreply,
     socket
     |> assign(
       property_features: updated_features,
       show_feature_picker_modal: false
     )}
  end

  def handle_info({:feature_selected, feature}, socket) do
    current_features = socket.assigns.property_features

    updated_features =
      if Enum.any?(current_features, &(&1.id == feature.id)),
        do: current_features,
        else: current_features ++ [feature]

    {:noreply,
     socket
     |> assign(
       property_features: updated_features,
       show_feature_picker_modal: false
     )}
  end

  defp parse_page(nil), do: 1

  defp parse_page(page_str) do
    case Integer.parse(page_str) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp load_supporting_data(socket) do
    tenant = socket.assigns[:current_user].organization.domain

    markets =
      Market
      |> Ash.Query.for_read(:list_all, %{}, tenant: tenant)
      |> Ash.read!()
      |> Enum.map(&{&1.name, &1.id})

    accounts =
      Account
      |> Ash.Query.for_read(:read, %{}, tenant: tenant)
      |> Ash.read!()

    assign(socket, markets: markets, accounts: accounts)
  end

  defp load_properties(socket) do
    tenant = socket.assigns.tenant
    page = socket.assigns.page
    limit = socket.assigns.page_size
    offset = (page - 1) * limit
    search_query = String.trim(socket.assigns.search_query)

    query =
      Property
      |> Ash.Query.for_read(:read, %{}, tenant: tenant)
      |> Ash.Query.sort(name: :asc)

    query =
      if search_query == "" do
        query
      else
        pattern = "%#{search_query}%"
        Ash.Query.filter(query, fragment("? ILIKE ?", name, ^pattern))
      end

    page_result =
      query
      |> Ash.Query.page(limit: limit, offset: offset, count: true)
      |> Ash.read!(tenant: tenant)

    count_query = Ash.Query.unset(query, [:sort, :limit, :offset])
    total_count = Ash.count!(count_query, tenant: tenant, domain: AshPhoenixStarter.Properties)

    properties =
      query
      |> Ash.Query.load([:market])
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)
      |> Ash.read!(domain: AshPhoenixStarter.Properties)

    total_pages = max(ceil(total_count / limit), 1)

    assign(socket,
      properties: properties,
      total_count: total_count,
      total_pages: total_pages
    )
  end

  @impl true
  def handle_event("set_modal_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, modal_tab: String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("open_file_picker_modal", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, show_file_picker_modal: true, picker_mode: mode)}
  end

  def handle_event("close_file_picker_modal", _, socket) do
    {:noreply, assign(socket, show_file_picker_modal: false, picker_mode: nil)}
  end

  def handle_event("open_service_picker_modal", _, socket) do
    {:noreply, assign(socket, show_service_picker_modal: true)}
  end

  def handle_event("close_service_picker_modal", _, socket) do
    {:noreply, assign(socket, show_service_picker_modal: false)}
  end

  def handle_event("open_feature_picker_modal", _, socket) do
    {:noreply, assign(socket, show_feature_picker_modal: true)}
  end

  def handle_event("close_feature_picker_modal", _, socket) do
    {:noreply, assign(socket, show_feature_picker_modal: false)}
  end

  #  def handle_event("set_primary_image", %{"id" => id}, socket) do
  #    {:noreply, assign(socket, primary_image_id: id)}
  #  end

  def handle_event("remove_image", %{"id" => id}, socket) do
    updated = Enum.reject(socket.assigns.property_images, &(&1.id == id))

    primary_id =
      if socket.assigns.primary_image_id == id do
        case List.first(updated) do
          nil -> nil
          file -> file.id
        end
      else
        socket.assigns.primary_image_id
      end

    {:noreply, assign(socket, property_images: updated, primary_image_id: primary_id)}
  end

  def handle_event("remove_property_service", %{"id" => id}, socket) do
    updated = Enum.reject(socket.assigns.property_services, &(&1.id == id))
    {:noreply, assign(socket, property_services: updated)}
  end

  def handle_event("remove_property_feature", %{"id" => id}, socket) do
    updated = Enum.reject(socket.assigns.property_features, &(&1.id == id))
    {:noreply, assign(socket, property_features: updated)}
  end

  def handle_event("open_new", _, socket) do
    tenant = socket.assigns.tenant
    current_user_id = socket.assigns.current_user.id

    form =
      Property
      |> AshPhoenix.Form.for_create(:create,
        as: "property",
        tenant: tenant,
        domain: AshPhoenixStarter.Properties,
        values: %{owner_id: current_user_id}
      )

    {:noreply,
     assign(socket,
       form: to_form(form),
       property: nil,
       page_title: "Add New Property",
       modal_type: :edit,
       modal_tab: :details,
       property_images: [],
       primary_image_id: nil,
       property_features: [],
       property_services: [],
       show_file_picker_modal: false,
       show_service_picker_modal: false,
       show_feature_picker_modal: false,
       picker_mode: nil
     )}
  end

  def handle_event("open_modal", %{"id" => id, "type" => type}, socket) do
    tenant = socket.assigns.tenant

    property =
      Ash.get!(Property, id,
        tenant: tenant,
        load: [images: :asset, primary_image: [], services: [:primary_image], features: []]
      )

    modal_type = String.to_existing_atom(type)

    form =
      if modal_type == :edit do
        AshPhoenix.Form.for_update(property, :update,
          as: "property",
          tenant: tenant,
          domain: AshPhoenixStarter.Properties
        )
      else
        nil
      end

    #   form = AshPhoenix.Form.for_update(property, :update, as: "property", tenant: tenant)
    images = Enum.map(property.images, & &1.asset)
    services = if property.services, do: property.services, else: []
    features = if property.features, do: property.features, else: []

    {:noreply,
     assign(socket,
       form: to_form(form),
       property: property,
       modal_type: modal_type,
       page_title: "Edit Property",
       modal_tab: :details,
       property_images: images,
       primary_image_id: property.primary_image_id,
       property_features: features,
       property_services: services,
       show_file_picker_modal: false,
       show_service_picker_modal: false,
       show_feature_picker_modal: false,
       picker_mode: nil
     )}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply,
     assign(socket,
       modal_type: nil,
       modal_tab: :details,
       form: nil,
       property: nil,
       property_images: [],
       primary_image_id: nil,
       show_file_picker_modal: false,
       picker_mode: nil,
       show_service_picker_modal: false,
       property_services: [],
       show_feature_picker_modal: false,
       property_features: []
     )}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    property = Ash.get!(Property, id, tenant: tenant, domain: AshPhoenixStarter.Properties)

    case Ash.destroy(property,
           tenant: tenant,
           domain: AshPhoenixStarter.Properties,
           authorize?: false
         ) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Property deleted successfully.")
         |> assign(
           modal_type: nil,
           modal_tab: :details,
           form: nil,
           property: nil,
           property_images: [],
           primary_image_id: nil,
           show_file_picker_modal: false,
           picker_mode: nil,
           show_service_picker_modal: false,
           property_services: [],
           show_feature_picker_modal: false,
           property_features: []
         )
         |> load_properties()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to delete Property.")}
    end
  end

  def handle_event("search", %{"search_query" => query}, socket) do
    {:noreply,
     socket
     |> assign(search_query: query, page: 1)
     |> load_properties()}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    property = Ash.get!(Property, id, tenant: tenant)
    new_active = !property.active
    IO.inspect(new_active, label: "new_active")

    case property
         |> Ash.Changeset.for_update(:update, %{active: new_active}, tenant: tenant)
         |> Ash.update() do
      {:ok, _updated_property} ->
        status_label = if new_active, do: "active", else: "inactive"

        {:noreply,
         socket
         |> put_flash(:info, "Property status updated to #{status_label}.")
         |> load_properties()}

      {:error, changeset} ->
        IO.inspect(changeset, label: "changeset")
        {:noreply, put_flash(socket, :error, "Failed to update property status.")}
    end
  end

  @impl true
  def handle_event("validate", %{"property" => property_params}, socket) do
    form =
      socket.assigns.form
      |> AshPhoenix.Form.validate(property_params)

    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", params, socket) do
    property_params =
      case params do
        %{"property" => p_params} ->
          p_params

        _ ->
          case socket.assigns[:form] do
            %{source: %{params: p}} when not is_nil(p) -> p
            _ -> %{}
          end
      end

    save(property_params, socket)
  end

  defp save(property_params, socket) do
    tenant = socket.assigns.tenant
    current_user_id = socket.assigns.current_user.id
    property_params = Map.put_new(property_params, "owner_id", current_user_id)
    merged_params = Map.put(property_params, "primary_image_id", socket.assigns.primary_image_id)

    case AshPhoenix.Form.submit(socket.assigns.form, params: merged_params) do
      {:ok, property} ->
        # Sync Images
        existing_relations =
          AshPhoenixStarter.Properties.Property.Image
          |> Ash.Query.for_read(:read, %{}, tenant: tenant, domain: AshPhoenixStarter.Properties)
          |> Ash.Query.filter(property_id == ^property.id)
          |> Ash.read!(domain: AshPhoenixStarter.Properties)

        existing_relations
        |> Enum.each(fn rel ->
          unless Enum.any?(socket.assigns.property_images, &(&1.id == rel.asset_id)) do
            Ash.destroy!(rel, tenant: tenant, domain: AshPhoenixStarter.Properties)
          end
        end)

        Enum.each(socket.assigns.property_images, fn file ->
          unless Enum.any?(
                   existing_relations,
                   &(&1.property_id == property.id and &1.asset_id == file.id)
                 ) do
            AshPhoenixStarter.Properties.Property.Image
            |> Ash.Changeset.for_create(:create, %{property_id: property.id, asset_id: file.id},
              tenant: tenant,
              domain: AshPhoenixStarter.Properties
            )
            |> Ash.create!(domain: AshPhoenixStarter.Properties)
          end
        end)

        # Sync Services
        existing_services =
          AshPhoenixStarter.Properties.Service
          |> Ash.Query.for_read(:read, %{}, tenant: tenant, domain: AshPhoenixStarter.Properties)
          |> Ash.Query.filter(property_id == ^property.id)
          |> Ash.read!(domain: AshPhoenixStarter.Properties)

        existing_services
        |> Enum.each(fn rel ->
          unless Enum.any?(socket.assigns.property_services, &(&1.id == rel.service_id)) do
            Ash.destroy!(rel, tenant: tenant, domain: AshPhoenixStarter.Properties)
          end
        end)

        Enum.each(socket.assigns.property_services, fn service ->
          unless Enum.any?(
                   existing_services,
                   &(&1.property_id == property.id and &1.service_id == service.id)
                 ) do
            AshPhoenixStarter.Properties.Service
            |> Ash.Changeset.for_create(
              :create,
              %{property_id: property.id, service_id: service.id},
              tenant: tenant,
              domain: AshPhoenixStarter.Properties
            )
            |> Ash.create!(domain: AshPhoenixStarter.Properties)
          end
        end)

        existing_features =
          AshPhoenixStarter.Properties.Feature
          |> Ash.Query.for_read(:read, %{}, tenant: tenant, domain: AshPhoenixStarter.Properties)
          |> Ash.Query.filter(property_id == ^property.id)
          |> Ash.read!(domain: AshPhoenixStarter.Properties)

        existing_features
        |> Enum.each(fn rel ->
          unless Enum.any?(socket.assigns.property_features, &(&1.id == rel.feature_id)) do
            Ash.destroy!(rel, tenant: tenant, domain: AshPhoenixStarter.Properties)
          end
        end)

        Enum.each(socket.assigns.property_features, fn feature ->
          unless Enum.any?(
                   existing_features,
                   &(&1.property_id == property.id and &1.feature_id == feature.id)
                 ) do
            AshPhoenixStarter.Properties.Feature
            |> Ash.Changeset.for_create(
              :create,
              %{property_id: property.id, feature_id: feature.id},
              tenant: tenant,
              domain: AshPhoenixStarter.Properties
            )
            |> Ash.create!(domain: AshPhoenixStarter.Properties)
          end
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Property saved successfully.")
         |> assign(
           modal_type: nil,
           form: nil,
           property: nil,
           modal_tab: :details,
           property_images: [],
           primary_image_id: nil,
           property_features: [],
           property_services: [],
           show_file_picker_modal: false,
           show_service_picker_modal: false,
           show_feature_picker_modal: false,
           picker_mode: nil
         )
         |> load_properties()}

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
            <h1 class="text-2xl font-bold text-white">Admin Properties Management</h1>
            <p class="text-sm text-gray-400 mt-1">
              Review, update, or inspect all properties across the system.
            </p>
          </div>
          <.button
            phx-click="open_new"
            class="bg-black text-white border border-neutral-800 px-4 py-2 rounded-lg text-sm font-medium hover:bg-neutral-900 transition-colors"
          >
            + Add New Property
          </.button>
        </div>

        <div class="mb-6 max-w-md">
          <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
            Filter Properties
          </label>
          <form phx-change="search" phx-submit="search">
            <input
              type="text"
              name="search_query"
              value={@search_query}
              placeholder="Filter by property name..."
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
                  Property Name
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Address
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Type / Units
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Status
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
              <%= for property <- @properties do %>
                <tr class="hover:bg-neutral-900/40 transition-colors">
                  <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-white sm:pl-6">
                    {property.name}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-400">
                    {property.address_line1 || "No address provided"}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-400">
                    {property.property_type || "Standard"}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm">
                    <.button
                      phx-click="toggle_active"
                      phx-value-id={property.id}
                      class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium bg-black text-white border border-neutral-700 cursor-pointer hover:border-white transition-colors"
                    >
                      {if property.active, do: :active, else: :inactive}
                    </.button>
                  </td>
                  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6 space-x-2">
                    <.button
                      phx-click="open_modal"
                      phx-value-id={property.id}
                      phx-value-type="edit"
                      class="text-white hover:text-gray-300 bg-black hover:bg-neutral-900 border border-neutral-800 px-3 py-1.5 rounded-md text-xs font-medium transition-colors"
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
                <.link
                  patch={~p"/admin/properties?page={@page - 1}&search_query={@search_query}"}
                  class="px-3 py-1.5 bg-black border border-neutral-800 rounded-md text-xs font-medium text-white hover:bg-neutral-900"
                >
                  Previous
                </.link>
              <% end %>
              <%= if @page < @total_pages do %>
                <.link
                  patch={~p"/admin/properties?page={@page + 1}&search_query={@search_query}"}
                  class="px-3 py-1.5 bg-black border border-neutral-800 rounded-md text-xs font-medium text-white hover:bg-neutral-900"
                >
                  Next
                </.link>
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
      
    <!-- MAIN PROPERTY MODAL -->
      <%= if @modal_type do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md overflow-y-auto py-10">
          <div class="bg-black text-white rounded-2xl shadow-2xl w-full max-w-2xl overflow-hidden border border-neutral-800 my-auto">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-black">
              <h3 class="text-lg font-semibold text-white">
                {if @property, do: "Edit Property", else: "Add New Property"}
              </h3>
              <.button
                phx-click="close_modal"
                class="text-gray-400 hover:text-white text-sm font-medium"
              >
                ✕
              </.button>
            </div>
            
    <!-- Modal Navigation Tabs -->
            <div class="flex border-b border-neutral-800 bg-neutral-950 px-6 gap-6 overflow-x-auto">
              <button
                phx-click="set_modal_tab"
                phx-value-tab="details"
                class={[
                  "py-3 text-xs font-semibold uppercase tracking-wider border-b-2 transition-colors cursor-pointer whitespace-nowrap",
                  @modal_tab == :details && "border-white text-white",
                  @modal_tab != :details && "border-transparent text-gray-400 hover:text-gray-200"
                ]}
              >
                Details
              </button>
              <button
                phx-click="set_modal_tab"
                phx-value-tab="images"
                class={[
                  "py-3 text-xs font-semibold uppercase tracking-wider border-b-2 transition-colors cursor-pointer whitespace-nowrap",
                  @modal_tab == :images && "border-white text-white",
                  @modal_tab != :images && "border-transparent text-gray-400 hover:text-gray-200"
                ]}
              >
                Images {if length(@property_images) > 0, do: "(#{length(@property_images)})", else: ""}
              </button>
              <button
                phx-click="set_modal_tab"
                phx-value-tab="features"
                class={[
                  "py-3 text-xs font-semibold uppercase tracking-wider border-b-2 transition-colors cursor-pointer whitespace-nowrap",
                  @modal_tab == :features && "border-white text-white",
                  @modal_tab != :features && "border-transparent text-gray-400 hover:text-gray-200"
                ]}
              >
                Features {if length(@property_features) > 0,
                  do: "(#{length(@property_features)})",
                  else: ""}
              </button>
              <button
                phx-click="set_modal_tab"
                phx-value-tab="services"
                class={[
                  "py-3 text-xs font-semibold uppercase tracking-wider border-b-2 transition-colors cursor-pointer whitespace-nowrap",
                  @modal_tab == :services && "border-white text-white",
                  @modal_tab != :services && "border-transparent text-gray-400 hover:text-gray-200"
                ]}
              >
                Services {if length(@property_services) > 0,
                  do: "(#{length(@property_services)})",
                  else: ""}
              </button>
            </div>

            <.form
              for={@form}
              id="property-form"
              phx-change="validate"
              phx-submit="save"
              class="p-6 space-y-6 max-h-[65vh] overflow-y-auto bg-black text-white"
            >
              <!-- DETAILS TAB CONTENT -->
              <%= if @modal_tab == :details do %>
                <div class="space-y-6">
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div>
                      <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                        Property Name
                      </label>
                      <.input
                        field={@form[:name]}
                        type="text"
                        placeholder="Grand Resort or Sunset Apartments"
                        class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                      />
                    </div>

                    <div>
                      <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                        Property Type
                      </label>
                      <.input
                        field={@form[:property_type]}
                        type="select"
                        options={[
                          {"Single Family Home", :single_family_home},
                          {"Multi Family", :multi_family},
                          {"Condominium", :condominium},
                          {"Townhouse", :townhouse},
                          {"Commercial", :commercial},
                          {"Industrial", :industrial},
                          {"Land", :land},
                          {"Hotel", :hotel}
                        ]}
                        class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                      />
                    </div>
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div class="sm:col-span-2">
                      <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                        Address Line 1
                      </label>
                      <.input
                        field={@form[:address_line1]}
                        type="text"
                        placeholder="123 Main St"
                        class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                      />
                    </div>
                    <div>
                      <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                        City
                      </label>
                      <.input
                        field={@form[:city]}
                        type="text"
                        placeholder="Tucson"
                        class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                      />
                    </div>
                  </div>

                  <div class="grid grid-cols-3 gap-4">
                    <div>
                      <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                        State
                      </label>
                      <.input
                        field={@form[:state]}
                        type="text"
                        placeholder="AZ"
                        class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                      />
                    </div>
                    <div>
                      <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                        Postal Code
                      </label>
                      <.input
                        field={@form[:postal_code]}
                        type="text"
                        placeholder="85701"
                        class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                      />
                    </div>
                    <div>
                      <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                        Market
                      </label>
                      <.input
                        field={@form[:market_id]}
                        type="select"
                        options={@markets}
                        class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                      />
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- IMAGES TAB CONTENT -->
              <%= if @modal_tab == :images do %>
                <div class="space-y-6">
                  <div>
                    <h4 class="text-sm font-semibold text-white">Property Images & Primary Cover</h4>
                    <p class="text-xs text-gray-400 mt-0.5">
                      Manage your gallery images and choose a primary cover image for the property.
                    </p>
                  </div>

                  <div class="flex items-start gap-4">
                    <!-- Primary Cover Slot -->
                    <div class="space-y-1">
                      <span class="block text-[10px] text-gray-400 uppercase font-semibold">
                        Primary Cover
                      </span>
                      <% primary_img =
                        Enum.find(@property_images, &(&1.id == @primary_image_id)) ||
                          List.first(@property_images) %>
                      <div class="relative w-32 h-32 bg-neutral-900 rounded-lg border border-neutral-800 overflow-hidden flex items-center justify-center">
                        <%= if primary_img do %>
                          <img src={primary_img.file_url} class="object-cover w-full h-full" />
                          <.button
                            phx-click="open_file_picker_modal"
                            phx-value-mode="primary"
                            class="absolute inset-x-0 bottom-0 bg-black/70 hover:bg-black text-[10px] py-1 text-center font-medium text-white transition-colors cursor-pointer"
                          >
                            Change Cover
                          </.button>
                        <% else %>
                          <.button
                            phx-click="open_file_picker_modal"
                            phx-value-mode="primary"
                            class="w-full h-full flex flex-col items-center justify-center text-gray-400 hover:text-white transition-colors cursor-pointer"
                          >
                            <span class="text-xl">+</span>
                            <span class="text-[10px] uppercase font-medium mt-1">Set Cover</span>
                          </.button>
                        <% end %>
                      </div>
                    </div>
                    
    <!-- Gallery Images Grid / Add Trigger (Primary Excluded) -->
                    <div class="flex-1 space-y-1">
                      <span class="block text-[10px] text-gray-400 uppercase font-semibold">
                        Gallery Images
                      </span>
                      <div class="grid grid-cols-3 gap-2">
                        <%= for img <- Enum.reject(@property_images, &(&1.id == @primary_image_id)) do %>
                          <div class="relative group h-32 bg-neutral-900 rounded-lg border border-neutral-800 overflow-hidden flex items-center justify-center">
                            <img src={img.file_url} class="object-cover w-full h-full" />
                            <.button
                              phx-click="remove_image"
                              phx-value-id={img.id}
                              class="absolute top-1 right-1 bg-black/70 text-white rounded-full p-1 text-[10px] hover:bg-red-600 transition-colors cursor-pointer"
                            >
                              ✕
                            </.button>
                          </div>
                        <% end %>

                        <.button
                          phx-click="open_file_picker_modal"
                          phx-value-mode="gallery"
                          class="h-32 border-2 border-dashed border-neutral-800 rounded-lg flex flex-col items-center justify-center text-gray-400 hover:border-white hover:text-white transition-all bg-black/50 cursor-pointer"
                        >
                          <span class="text-xl">+</span>
                          <span class="text-[10px] uppercase font-medium mt-1">Add Images</span>
                        </.button>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- TAB 4: FEATURES -->
              <%= if @modal_tab == :features do %>
                <div class="space-y-4">
                  <div class="flex justify-between items-center bg-neutral-950 p-3 rounded-xl border border-neutral-800">
                    <div>
                      <h4 class="text-xs font-semibold text-white uppercase">Assigned Features</h4>
                      <p class="text-[10px] text-gray-400">Manage features tied to this property</p>
                    </div>
                    <.button
                      phx-click="open_feature_picker_modal"
                      class="px-3.5 py-2 bg-white text-black hover:bg-gray-200 rounded-lg text-xs font-semibold transition-colors cursor-pointer shadow-sm"
                    >
                      + Select Features
                    </.button>
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-2">
                    <%= for feature <- @property_features do %>
                      <div class="relative group bg-neutral-900 border border-neutral-800 rounded-xl p-2.5 flex items-center space-x-3">
                        <div class="truncate flex-1">
                          <h5 class="text-xs font-medium text-white truncate">{feature.name}</h5>
                          <p class="text-[10px] text-gray-400 truncate">
                            {feature.description || "Feature"}
                          </p>
                        </div>
                        <.button
                          phx-click="remove_property_feature"
                          phx-value-id={feature.id}
                          class="absolute top-1.5 right-1.5 bg-black/80 hover:bg-red-600 text-white rounded-full w-5 h-5 flex items-center justify-center text-[10px] transition-colors cursor-pointer shadow-md"
                          title="Remove feature"
                        >
                          ✕
                        </.button>
                      </div>
                    <% end %>
                    <%= if Enum.empty?(@property_features) do %>
                      <div class="col-span-full py-8 text-center border border-dashed border-neutral-800 rounded-xl text-gray-500 text-xs">
                        No features assigned yet. Click "+ Select Features" above to add.
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
              
    <!-- SERVICES TAB CONTENT -->
              <%= if @modal_tab == :services do %>
                <div class="space-y-4">
                  <div class="flex justify-between items-center bg-neutral-950 p-3 rounded-xl border border-neutral-800">
                    <div>
                      <h4 class="text-xs font-semibold text-white uppercase">Assigned Services</h4>
                      <p class="text-[10px] text-gray-400">Manage services tied to this property</p>
                    </div>
                    <.button
                      phx-click="open_service_picker_modal"
                      class="px-3.5 py-2 bg-white text-black hover:bg-gray-200 rounded-lg text-xs font-semibold transition-colors cursor-pointer shadow-sm"
                    >
                      + Select Services
                    </.button>
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-2">
                    <%= for service <- @property_services do %>
                      <div class="relative group bg-neutral-900 border border-neutral-800 rounded-xl p-2.5 flex items-center space-x-3">
                        <div class="w-10 h-10 rounded-lg bg-neutral-800 overflow-hidden flex-shrink-0 flex items-center justify-center">
                          <%= if service.primary_image do %>
                            <img
                              src={service.primary_image.file_url}
                              class="w-full h-full object-cover"
                            />
                          <% else %>
                            <span class="text-[10px] text-gray-500 uppercase">Img</span>
                          <% end %>
                        </div>
                        <div class="truncate flex-1">
                          <h5 class="text-xs font-medium text-white truncate">{service.name}</h5>
                          <p class="text-[10px] text-gray-400 truncate">
                            {service.description || "Service"}
                          </p>
                        </div>
                        <.button
                          phx-click="remove_property_service"
                          phx-value-id={service.id}
                          class="absolute top-1.5 right-1.5 bg-black/80 hover:bg-red-600 text-white rounded-full w-5 h-5 flex items-center justify-center text-[10px] transition-colors cursor-pointer shadow-md"
                          title="Remove service"
                        >
                          ✕
                        </.button>
                      </div>
                    <% end %>
                    <%= if Enum.empty?(@property_services) do %>
                      <div class="col-span-full py-8 text-center border border-dashed border-neutral-800 rounded-xl text-gray-500 text-xs">
                        No services assigned yet. Click "+ Select Services" above to add.
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <div>
                <%= if @property do %>
                  <.button
                    phx-click="delete"
                    phx-value-id={@property.id}
                    class="px-4 py-2 border border-red-900/50 bg-red-950/30 text-red-400 rounded-lg text-sm font-medium hover:bg-red-900/40 cursor-pointer"
                  >
                    Delete Property
                  </.button>
                <% end %>
              </div>
              <div class="flex justify-end space-x-3 pt-4 border-t border-neutral-800">
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
                  Save Property
                </.button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
      
    <!-- SEPARATE FILE PICKER GRID COMPONENT DIALOG MODAL -->
      <%= if @show_file_picker_modal do %>
        <div class="fixed inset-0 z-[60] flex items-center justify-center bg-black/85 backdrop-blur-md p-4">
          <div class="bg-neutral-950 text-white rounded-2xl shadow-2xl w-full max-w-3xl overflow-hidden border border-neutral-800 flex flex-col max-h-[85vh]">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-black">
              <h3 class="text-base font-semibold uppercase text-gray-200">
                {if @picker_mode == "primary",
                  do: "Select Primary Cover Image",
                  else: "Upload & Attach Gallery Images"}
              </h3>
              <.button
                phx-click="close_file_picker_modal"
                class="text-gray-400 hover:text-white text-sm font-medium cursor-pointer"
              >
                ✕ Close
              </.button>
            </div>
            <div class="p-6 overflow-y-auto flex-1">
              <.live_component
                module={AshPhoenixStarterWeb.Components.FilePickerGridComponent}
                id="property-file-picker-grid"
                organization_id={@current_user.organization.id}
                tenant={@tenant}
              />
            </div>
          </div>
        </div>
      <% end %>
      
    <!-- SERVICE PICKER GRID COMPONENT DIALOG MODAL -->
      <%= if @show_service_picker_modal do %>
        <div class="fixed inset-0 z-[60] flex items-center justify-center bg-black/85 backdrop-blur-md p-4">
          <div class="bg-neutral-950 text-white rounded-2xl shadow-2xl w-full max-w-3xl overflow-hidden border border-neutral-800 flex flex-col max-h-[85vh]">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-black">
              <h3 class="text-base font-semibold uppercase text-gray-200">Select Services</h3>
              <.button
                phx-click="close_service_picker_modal"
                class="text-gray-400 hover:text-white text-sm font-medium cursor-pointer"
              >
                ✕ Close
              </.button>
            </div>
            <div class="p-6 overflow-y-auto flex-1">
              <.live_component
                module={AshPhoenixStarterWeb.Components.ServicePickerGridComponent}
                id="property-service-picker-grid"
                organization_id={@current_user.organization.id}
                tenant={@tenant}
              />
            </div>
          </div>
        </div>
      <% end %>
      
    <!-- FEATURE PICKER GRID COMPONENT DIALOG MODAL -->
      <%= if @show_feature_picker_modal do %>
        <div class="fixed inset-0 z-[60] flex items-center justify-center bg-black/85 backdrop-blur-md p-4">
          <div class="bg-neutral-950 text-white rounded-2xl shadow-2xl w-full max-w-3xl overflow-hidden border border-neutral-800 flex flex-col max-h-[85vh]">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-black">
              <h3 class="text-base font-semibold uppercase text-gray-200">Select Features</h3>
              <.button
                phx-click="close_feature_picker_modal"
                class="text-gray-400 hover:text-white text-sm font-medium cursor-pointer"
              >
                ✕ Close
              </.button>
            </div>
            <div class="p-6 overflow-y-auto flex-1">
              <.live_component
                module={AshPhoenixStarterWeb.Components.FeaturePickerGridComponent}
                id="property-feature-picker-grid"
                tenant={@tenant}
              />
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
