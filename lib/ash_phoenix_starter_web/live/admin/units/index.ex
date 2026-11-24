defmodule AshPhoenixStarterWeb.Admin.Units.Index do
  use AshPhoenixStarterWeb, :live_view

  alias AshPhoenixStarter.Properties.Unit
  alias AshPhoenixStarter.Properties.Property

  import Ash.Query

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns[:current_user].organization.domain
    properties = Property |> Ash.Query.for_read(:read, %{}, tenant: tenant) |> Ash.read!()

    {:ok,
     socket
     |> assign(
       search_query: "",
       property_filter: "",
       page: 1,
       page_size: @page_size,
       page_title: "Admin - Units Directory",
       tenant: tenant,
       properties: properties,
       unit: nil,
       form: nil,
       show_modal: false,
       unit_images: [],
       primary_image_id: nil,
       show_file_picker_modal: false,
       picker_mode: nil
     )
     |> load_units()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tenant = socket.assigns.tenant
    page = parse_page(params["page"])

    socket =
      socket
      |> assign(page: page)
      |> load_units()

    socket =
      case socket.assigns.live_action do
        :new ->
          form = AshPhoenix.Form.for_create(Unit, :create, as: "unit", tenant: tenant)

          assign(socket,
            form: to_form(form),
            page_title: "Add New Unit",
            show_modal: true,
            unit_images: [],
            primary_image_id: nil,
            show_file_picker_modal: false,
            picker_mode: nil
          )

        :edit ->
          unit =
            Ash.get!(Unit, params["id"],
              tenant: tenant,
              load: [images: :asset, primary_image: []]
            )

          form = AshPhoenix.Form.for_update(unit, :update, as: "unit", tenant: tenant)
          images = Enum.map(unit.images, & &1.asset)

          assign(socket,
            unit: unit,
            form: to_form(form),
            page_title: "Edit Unit",
            show_modal: true,
            unit_images: images,
            primary_image_id: unit.primary_image_id,
            show_file_picker_modal: false,
            picker_mode: nil
          )

        _ ->
          assign(socket,
            form: nil,
            page_title: "Admin - Units Directory",
            show_modal: false,
            unit_images: [],
            primary_image_id: nil,
            show_file_picker_modal: false,
            picker_mode: nil
          )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:file_selected, file}, socket) do
    current_images = socket.assigns.unit_images
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

    {:noreply,
     socket
     |> assign(
       unit_images: updated_images,
       primary_image_id: primary_id,
       show_file_picker_modal: false,
       picker_mode: nil
     )}
  end

  defp parse_page(nil), do: 1

  defp parse_page(page_str) do
    case Integer.parse(page_str) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp load_units(socket) do
    tenant = socket.assigns.tenant
    page = socket.assigns.page
    limit = socket.assigns.page_size
    offset = (page - 1) * limit
    search_query = String.trim(socket.assigns.search_query)
    property_filter = socket.assigns.property_filter

    query =
      Unit
      |> Ash.Query.for_read(:read, %{}, tenant: tenant)
      |> Ash.Query.load(:property)
      |> Ash.Query.sort(inserted_at: :desc)

    query =
      if search_query == "" do
        query
      else
        downcased_query = "%#{String.downcase(search_query)}%"

        Ash.Query.filter(
          query,
          contains(fragment("lower(?)", name), ^downcased_query) or
            contains(fragment("lower(?)", unit_number), ^downcased_query)
        )
      end

    query =
      if property_filter == "" or is_nil(property_filter) do
        query
      else
        Ash.Query.filter(query, property_id == ^property_filter)
      end

    count_query = Ash.Query.unset(query, [:sort, :limit, :offset, :load])
    total_count = Ash.count!(count_query, tenant: tenant)

    units =
      query
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)
      |> Ash.read!()

    total_pages = max(ceil(total_count / limit), 1)

    assign(socket,
      units: units,
      total_count: total_count,
      total_pages: total_pages
    )
  end

  @impl true
  def handle_event("toggle_modal", _, socket) do
    {:noreply,
     assign(socket,
       show_modal: !socket.assigns.show_modal,
       show_file_picker_modal: false,
       picker_mode: nil
     )}
  end

  @impl true
  def handle_event("open_file_picker_modal", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, show_file_picker_modal: true, picker_mode: mode)}
  end

  def handle_event("close_file_picker_modal", _, socket) do
    {:noreply, assign(socket, show_file_picker_modal: false, picker_mode: nil)}
  end

  def handle_event("remove_image", %{"id" => id}, socket) do
    updated = Enum.reject(socket.assigns.unit_images, &(&1.id == id))

    primary_id =
      if socket.assigns.primary_image_id == id do
        case List.first(updated) do
          nil -> nil
          file -> file.id
        end
      else
        socket.assigns.primary_image_id
      end

    {:noreply, assign(socket, unit_images: updated, primary_image_id: primary_id)}
  end

  def handle_event("open_new", _, socket) do
    tenant = socket.assigns.tenant
    form = AshPhoenix.Form.for_create(Unit, :create, as: "unit", tenant: tenant)

    {:noreply,
     assign(socket,
       form: to_form(form),
       unit: nil,
       show_modal: true,
       page_title: "Add New Unit",
       unit_images: [],
       primary_image_id: nil,
       show_file_picker_modal: false,
       picker_mode: nil
     )}
  end

  def handle_event("open_edit", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    unit = Ash.get!(Unit, id, tenant: tenant, load: [images: :asset, primary_image: []])
    form = AshPhoenix.Form.for_update(unit, :update, as: "unit", tenant: tenant)
    images = Enum.map(unit.images, & &1.asset)

    {:noreply,
     assign(socket,
       form: to_form(form),
       unit: unit,
       show_modal: true,
       page_title: "Edit Unit",
       unit_images: images,
       primary_image_id: unit.primary_image_id,
       show_file_picker_modal: false,
       picker_mode: nil
     )}
  end

  def handle_event("search", %{"search_query" => query}, socket) do
    {:noreply,
     socket
     |> assign(search_query: query, page: 1)
     |> load_units()}
  end

  def handle_event("filter_property", %{"property_id" => property_id}, socket) do
    {:noreply,
     socket
     |> assign(property_filter: property_id, page: 1)
     |> load_units()}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    unit = Ash.get!(Unit, id, tenant: tenant)
    new_active = !unit.active

    case unit
         |> Ash.Changeset.for_update(:update, %{active: new_active}, tenant: tenant)
         |> Ash.update() do
      {:ok, _updated_unit} ->
        status_label = if new_active, do: "active", else: "inactive"

        {:noreply,
         socket
         |> put_flash(:info, "Unit status updated to #{status_label}.")
         |> load_units()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update unit status.")}
    end
  end

  @impl true
  def handle_event("validate", %{"unit" => unit_params}, socket) do
    form =
      socket.assigns.form
      |> AshPhoenix.Form.validate(unit_params)

    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"unit" => unit_params}, socket) do
    tenant = socket.assigns.tenant
    merged_params = Map.put(unit_params, "primary_image_id", socket.assigns.primary_image_id)

    case AshPhoenix.Form.submit(socket.assigns.form, params: merged_params) do
      {:ok, unit} ->
        existing_relations =
          Ash.read!(
            Ash.Query.for_read(AshPhoenixStarter.Properties.UnitImage, :read, %{}, tenant: tenant)
          )

        existing_relations
        |> Enum.filter(&(&1.property_unit_id == unit.id))
        |> Enum.each(fn rel ->
          unless Enum.any?(socket.assigns.unit_images, &(&1.id == rel.asset_id)) do
            Ash.destroy!(rel, tenant: tenant)
          end
        end)

        Enum.each(socket.assigns.unit_images, fn file ->
          unless Enum.any?(
                   existing_relations,
                   &(&1.property_unit_id == unit.id and &1.asset_id == file.id)
                 ) do
            AshPhoenixStarter.Properties.UnitImage
            |> Ash.Changeset.for_create(:create, %{property_unit_id: unit.id, asset_id: file.id},
              tenant: tenant
            )
            |> Ash.create!()
          end
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Unit saved successfully.")
         |> assign(
           show_modal: false,
           form: nil,
           unit: nil,
           unit_images: [],
           primary_image_id: nil,
           show_file_picker_modal: false,
           picker_mode: nil
         )
         |> load_units()}

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
            <h1 class="text-2xl font-bold text-white">Admin Units Management</h1>
            <p class="text-sm text-gray-400 mt-1">
              Review, update, or inspect all property units.
            </p>
          </div>
          <.button
            phx-click="open_new"
            class="bg-black text-white border border-neutral-800 px-4 py-2 rounded-lg text-sm font-medium hover:bg-neutral-900 transition-colors"
          >
            + Add New Unit
          </.button>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6 max-w-2xl">
          <div>
            <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
              Filter Units
            </label>
            <form phx-change="search" phx-submit="search">
              <input
                type="text"
                name="search_query"
                value={@search_query}
                placeholder="Filter by name or unit number..."
                phx-debounce="150"
                autocomplete="off"
                class="w-full rounded-lg bg-black border border-neutral-800 px-4 py-2 text-white text-sm shadow-sm focus:ring-white focus:border-white placeholder-gray-500"
              />
            </form>
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
              Filter by Property
            </label>
            <form phx-change="filter_property">
              <select
                name="property_id"
                class="w-full rounded-lg bg-black border border-neutral-800 px-4 py-2 text-white text-sm shadow-sm focus:ring-white focus:border-white"
              >
                <option value="">All Properties</option>
                <%= for prop <- @properties do %>
                  <option value={prop.id} selected={@property_filter == prop.id}>{prop.name}</option>
                <% end %>
              </select>
            </form>
          </div>
        </div>

        <div class="bg-transparent shadow-sm ring-1 ring-neutral-800 sm:rounded-xl overflow-hidden">
          <table class="min-w-full divide-y divide-neutral-800">
            <thead class="bg-black/40">
              <tr>
                <th
                  scope="col"
                  class="py-3.5 pl-4 pr-3 text-left text-xs font-semibold text-white sm:pl-6"
                >
                  Unit Name / Number
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Property
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Type
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Status
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Active
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Bed / Bath / SqFt
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
              <%= for unit <- @units do %>
                <tr class="hover:bg-neutral-900/40 transition-colors">
                  <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-white sm:pl-6">
                    <div>{unit.name}</div>
                    <div class="text-xs text-gray-400">
                      Unit #{unit.unit_number} {if unit.floor, do: "(Floor #{unit.floor})"}
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-300">
                    {if unit.property, do: unit.property.name, else: "—"}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-300 capitalize">
                    {unit.unit_type}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm">
                    <span class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium bg-black text-white border border-neutral-700 capitalize">
                      {unit.status}
                    </span>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm">
                    <.button
                      phx-click="toggle_active"
                      phx-value-id={unit.id}
                      class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium bg-black text-white border border-neutral-700 cursor-pointer hover:border-white transition-colors"
                    >
                      {if unit.active, do: :active, else: :inactive}
                    </.button>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-300">
                    {unit.bedrooms || "—"} bd / {unit.bathrooms || "—"} ba / {unit.square_feet || "—"} sqft
                  </td>
                  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6 space-x-2">
                    <.button
                      phx-click="open_edit"
                      phx-value-id={unit.id}
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
                  patch={~p"/admin/units?page={@page - 1}"}
                  class="px-3 py-1.5 bg-black border border-neutral-800 rounded-md text-xs font-medium text-white hover:bg-neutral-900"
                >
                  Previous
                </.link>
              <% end %>
              <%= if @page < @total_pages do %>
                <.link
                  patch={~p"/admin/units?page={@page + 1}"}
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
      
    <!-- MAIN UNIT MODAL -->
      <%= if @show_modal and @form do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md overflow-y-auto py-10">
          <div class="bg-black text-white rounded-2xl shadow-2xl w-full max-w-2xl overflow-hidden border border-neutral-800 my-auto">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-black">
              <h3 class="text-lg font-semibold text-white">
                {if @unit, do: "Edit Unit", else: "Add New Unit"}
              </h3>
              <.button
                phx-click="toggle_modal"
                class="text-gray-400 hover:text-white text-sm font-medium"
              >
                ✕
              </.button>
            </div>

            <.form
              for={@form}
              id="unit-form"
              phx-change="validate"
              phx-submit="save"
              class="p-6 space-y-6 bg-black text-white max-h-[75vh] overflow-y-auto"
            >
              <%= if !@unit do %>
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Property
                  </label>
                  <.input
                    field={@form[:property_id]}
                    type="select"
                    options={Enum.map(@properties, &{&1.name, &1.id})}
                    prompt="Select Property"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
              <% end %>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Unit Name
                  </label>
                  <.input
                    field={@form[:name]}
                    type="text"
                    placeholder="e.g. Penthouse A"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Unit Number
                  </label>
                  <.input
                    field={@form[:unit_number]}
                    type="text"
                    placeholder="e.g. 402"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
              </div>
              
    <!-- Unit Images Preview and Selection Section -->
              <div class="space-y-4">
                <label class="block text-xs font-semibold text-gray-400 uppercase">
                  Unit Images & Primary Cover
                </label>

                <div class="flex items-start gap-4">
                  <!-- Primary Cover Slot -->
                  <div class="space-y-1">
                    <span class="block text-[10px] text-gray-400 uppercase font-semibold">
                      Primary Cover
                    </span>
                    <% primary_img =
                      Enum.find(@unit_images, &(&1.id == @primary_image_id)) ||
                        List.first(@unit_images) %>
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
                      <%= for img <- Enum.reject(@unit_images, &(&1.id == @primary_image_id)) do %>
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

              <div class="grid grid-cols-3 gap-4">
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Floor
                  </label>
                  <.input
                    field={@form[:floor]}
                    type="number"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Bedrooms
                  </label>
                  <.input
                    field={@form[:bedrooms]}
                    type="number"
                    step="0.5"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Bathrooms
                  </label>
                  <.input
                    field={@form[:bathrooms]}
                    type="number"
                    step="0.5"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Square Feet
                  </label>
                  <.input
                    field={@form[:square_feet]}
                    type="number"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Unit Type
                  </label>
                  <.input
                    field={@form[:unit_type]}
                    type="select"
                    options={[
                      {"Residential", :residential},
                      {"Commercial", :commercial},
                      {"Hotel Room", :hotel_room},
                      {"Suite", :suite},
                      {"Penthouse", :penthouse}
                    ]}
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
              </div>

              <div>
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">Status</label>
                <.input
                  field={@form[:status]}
                  type="select"
                  options={[
                    {"Vacant", :vacant},
                    {"Available", :available},
                    {"Occupied", :occupied},
                    {"Maintenance", :maintenance},
                    {"Reserved", :reserved},
                    {"Dirty", :dirty},
                    {"Off Market", :off_market}
                  ]}
                  class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                />
              </div>

              <div>
                <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">Notes</label>
                <.input
                  field={@form[:notes]}
                  type="textarea"
                  class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                />
              </div>

              <div class="flex justify-end space-x-3 pt-4 border-t border-neutral-800">
                <.button
                  phx-click="toggle_modal"
                  class="px-4 py-2 border border-neutral-800 rounded-lg text-sm font-medium text-white hover:bg-neutral-900 cursor-pointer"
                >
                  Cancel
                </.button>
                <.button
                  type="submit"
                  phx-disable-with="Saving..."
                  class="px-4 py-2 bg-white text-black rounded-lg text-sm font-medium hover:bg-gray-200 shadow-sm cursor-pointer"
                >
                  Save Unit
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
                id="unit-file-picker-grid"
                organization_id={@current_user.organization.id}
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
