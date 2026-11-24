defmodule AshPhoenixStarterWeb.Admin.Hotels.Index do
  use AshPhoenixStarterWeb, :live_view

  on_mount {AshPhoenixStarterWeb.LiveUserAuth, :live_user_required}

  alias AshPhoenixStarter.Hotels.Hotel
  alias AshPhoenixStarter.Accounts.User
  alias AshPhoenixStarter.Core.Market

  import PhiaUi.Components.Rating
  import Ash.Query

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns[:current_user].organization.domain

    owners =
      User
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.read!(authorize?: false)
      |> Enum.map(&{to_string(&1.email), &1.id})

    markets =
      Market
      |> Ash.Query.for_read(:list_all, %{}, tenant: tenant)
      |> Ash.read!()
      |> Enum.map(&{&1.name, &1.id})

    timezones =
      if Code.ensure_loaded?(Tzdata) do
        Tzdata.zone_list()
      else
        [
          "UTC",
          "America/New_York",
          "America/Chicago",
          "America/Denver",
          "America/Los_Angeles",
          "America/Phoenix",
          "Europe/London",
          "Europe/Paris",
          "Asia/Tokyo"
        ]
      end

    {:ok,
     socket
     |> assign(
       markets: markets,
       owners: owners,
       timezones: timezones,
       search_query: "",
       page: 1,
       page_size: @page_size,
       page_title: "Admin - Hotels Directory",
       tenant: tenant,
       hotel: nil,
       form: nil,
       show_modal: false,
       hotel_images: [],
       primary_image_id: nil,
       show_file_picker_modal: false,
       picker_mode: nil
     )
     |> load_supporting_data()
     |> load_hotels()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tenant = socket.assigns.tenant
    page = parse_page(params["page"])

    owners =
      User
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.read!(authorize?: false)
      |> Enum.map(&{to_string(&1.email), &1.id})

    socket =
      socket
      |> assign(page: page, owners: owners)
      |> load_hotels()

    socket =
      case socket.assigns.live_action do
        :new ->
          form = AshPhoenix.Form.for_create(Hotel, :create, as: "hotel", tenant: tenant)

          assign(socket,
            form: to_form(form),
            page_title: "Add New Hotel",
            show_modal: true,
            hotel_images: [],
            primary_image_id: nil,
            show_file_picker_modal: false,
            picker_mode: nil
          )

        :edit ->
          hotel =
            Ash.get!(Hotel, params["id"],
              tenant: tenant,
              load: [images: :asset, primary_image: []]
            )

          form = AshPhoenix.Form.for_update(hotel, :update, as: "hotel", tenant: tenant)
          images = Enum.map(hotel.images, & &1.asset)

          assign(socket,
            hotel: hotel,
            form: to_form(form),
            page_title: "Edit Hotel",
            show_modal: true,
            hotel_images: images,
            primary_image_id: hotel.primary_image_id,
            show_file_picker_modal: false,
            picker_mode: nil
          )

        _ ->
          assign(socket,
            form: nil,
            page_title: "Admin - Hotels Directory",
            show_modal: false,
            hotel_images: [],
            primary_image_id: nil,
            show_file_picker_modal: false,
            picker_mode: nil
          )
      end

    {:noreply, socket}
  end

  defp load_supporting_data(socket) do
    tenant = socket.assigns[:current_user].organization.domain

    markets =
      Market
      |> Ash.Query.for_read(:list_all, %{}, tenant: tenant)
      |> Ash.read!()
      |> Enum.map(&{&1.name, &1.id})

    assign(socket, markets: markets)
  end

  @impl true
  def handle_info({:file_selected, file}, socket) do
    current_images = socket.assigns.hotel_images
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
       hotel_images: updated_images,
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

  defp load_hotels(socket) do
    tenant = socket.assigns.tenant
    page = socket.assigns.page
    limit = socket.assigns.page_size
    offset = (page - 1) * limit
    search_query = String.trim(socket.assigns.search_query)

    query =
      Hotel
      |> Ash.Query.for_read(:read, %{}, tenant: tenant)
      |> Ash.Query.sort(name: :asc)

    query =
      if search_query == "" do
        query
      else
        pattern = "%#{search_query}%"
        Ash.Query.filter(query, fragment("? ILIKE ?", name, ^pattern))
      end

    # Fetch paginated results with count enabled
    page_result =
      query
      |> Ash.Query.page(limit: limit, offset: offset, count: true)
      |> Ash.Query.load([:market])
      |> Ash.read!(tenant: tenant)

    total_count = page_result.count || length(page_result.results)
    total_pages = max(ceil(total_count / limit), 1)

    assign(socket,
      hotels: page_result.results,
      total_count: total_count,
      total_pages: total_pages
    )
  end

  @impl true
  def handle_event("open_file_picker_modal", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, show_file_picker_modal: true, picker_mode: mode)}
  end

  def handle_event("close_file_picker_modal", _, socket) do
    {:noreply, assign(socket, show_file_picker_modal: false, picker_mode: nil)}
  end

  def handle_event("remove_image", %{"id" => id}, socket) do
    updated = Enum.reject(socket.assigns.hotel_images, &(&1.id == id))

    primary_id =
      if socket.assigns.primary_image_id == id do
        case List.first(updated) do
          nil -> nil
          file -> file.id
        end
      else
        socket.assigns.primary_image_id
      end

    {:noreply, assign(socket, hotel_images: updated, primary_image_id: primary_id)}
  end

  def handle_event("open_new", _, socket) do
    tenant = socket.assigns.tenant

    # Grab the first available market id as a safe default, or leave it blank if user must choose
    default_market_id =
      case socket.assigns.markets do
        [{_, id} | _] -> id
        _ -> nil
      end

    form =
      Hotel
      |> AshPhoenix.Form.for_create(:create,
        as: "hotel",
        tenant: tenant,
        domain: AshPhoenixStarter.Hotels,
        values: %{
          owner_id: socket.assigns.current_user.id,
          market_id: default_market_id
        }
      )

    {:noreply,
     assign(socket,
       form: to_form(form),
       hotel: nil,
       show_modal: true,
       page_title: "Add New Hotel",
       hotel_images: [],
       primary_image_id: nil,
       show_file_picker_modal: false,
       picker_mode: nil
     )}
  end

  def handle_event("open_edit", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    hotel = Ash.get!(Hotel, id, tenant: tenant, load: [images: :asset, primary_image: []])
    form = AshPhoenix.Form.for_update(hotel, :update, as: "hotel", tenant: tenant)
    images = Enum.map(hotel.images, & &1.asset)

    {:noreply,
     assign(socket,
       form: to_form(form),
       hotel: hotel,
       show_modal: true,
       page_title: "Edit Hotel",
       hotel_images: images,
       primary_image_id: hotel.primary_image_id,
       show_file_picker_modal: false,
       picker_mode: nil
     )}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply,
     assign(socket,
       show_modal: false,
       form: nil,
       hotel: nil,
       hotel_images: [],
       primary_image_id: nil,
       show_file_picker_modal: false,
       picker_mode: nil
     )}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    hotel = Ash.get!(Hotel, id, tenant: tenant)

    case Ash.destroy(hotel, tenant: tenant, authorize?: false) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Hotel deleted successfully.")
         |> assign(
           show_modal: false,
           form: nil,
           hotel: nil,
           hotel_images: [],
           primary_image_id: nil,
           show_file_picker_modal: false,
           picker_mode: nil
         )
         |> load_hotels()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to delete hotel.")}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant
    hotel = Ash.get!(Hotel, id, tenant: tenant)
    new_active = !hotel.active

    case hotel
         |> Ash.Changeset.for_update(:update, %{active: new_active}, authorize?: false)
         |> Ash.update(tenant: tenant) do
      {:ok, _updated_hotel} ->
        status_label = if new_active, do: "active", else: "inactive"

        {:noreply,
         socket
         |> put_flash(:info, "Hotel status changed to #{status_label}.")
         |> load_hotels()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to update hotel status.")}
    end
  end

  def handle_event("search", %{"search_query" => query}, socket) do
    {:noreply,
     socket
     |> assign(search_query: query, page: 1)
     |> load_hotels()}
  end

  def handle_event("change_page", %{"page" => page_str}, socket) do
    page = parse_page(page_str)

    {:noreply,
     socket
     |> assign(page: page)
     |> load_hotels()
     |> push_patch(to: ~p"/admin/hotels?page=#{page}")}
  end

  @impl true
  def handle_event("validate", %{"hotel" => hotel_params}, socket) do
    form =
      socket.assigns.form
      |> AshPhoenix.Form.validate(hotel_params)

    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("save", %{"hotel" => hotel_params}, socket) do
    tenant = socket.assigns.tenant
    merged_params = Map.put(hotel_params, "primary_image_id", socket.assigns.primary_image_id)

    case AshPhoenix.Form.submit(socket.assigns.form, params: merged_params) do
      {:ok, hotel} ->
        current_asset_ids = Enum.map(socket.assigns.hotel_images, & &1.id)

        hotel_with_images = Ash.load!(hotel, [images: :asset], tenant: tenant, authorize?: false)
        existing_asset_ids = Enum.map(hotel_with_images.images, & &1.asset_id)

        hotel_with_images.images
        |> Enum.reject(fn rel -> rel.asset_id in current_asset_ids end)
        |> Enum.each(fn rel ->
          Ash.Changeset.for_destroy(rel, :destroy, %{}, tenant: tenant, authorize?: false)
          |> Ash.destroy!()
        end)

        current_asset_ids
        |> Enum.reject(fn asset_id -> asset_id in existing_asset_ids end)
        |> Enum.each(fn asset_id ->
          Ash.Changeset.for_create(
            AshPhoenixStarter.Hotels.Hotel.Image,
            :create,
            %{hotel_id: hotel.id, asset_id: asset_id},
            tenant: tenant,
            authorize?: false
          )
          |> Ash.create!()
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Hotel saved successfully.")
         |> assign(
           show_modal: false,
           form: nil,
           hotel: nil,
           hotel_images: [],
           primary_image_id: nil,
           show_file_picker_modal: false,
           picker_mode: nil
         )
         |> load_hotels()}

      {:error, form} ->
        IO.inspect(form, label: "form")
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
            <h1 class="text-2xl font-bold text-white">Admin Hotels Management</h1>
            <p class="text-sm text-gray-400 mt-1">
              Review, update, or inspect all hotels across the system.
            </p>
          </div>
          <.button
            phx-click="open_new"
            class="bg-black text-white border border-neutral-800 px-4 py-2 rounded-lg text-sm font-medium hover:bg-neutral-900 transition-colors cursor-pointer"
          >
            + Add New Hotel
          </.button>
        </div>

        <div class="mb-6 max-w-md">
          <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
            Filter Hotels
          </label>
          <form phx-change="search" phx-submit="search">
            <input
              type="text"
              name="search_query"
              value={@search_query}
              placeholder="Filter by hotel name..."
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
                  Hotel Name
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Address
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Status
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold text-white">
                  Star Rating
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
              <%= for hotel <- @hotels do %>
                <tr class="hover:bg-neutral-900/40 transition-colors">
                  <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-white sm:pl-6">
                    {hotel.name}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-400">
                    {hotel.address_line1}
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm">
                    <button
                      phx-click="toggle_active"
                      phx-value-id={hotel.id}
                      class={[
                        "px-2.5 py-1 rounded-full text-xs font-semibold border transition-colors cursor-pointer",
                        hotel.active == :active &&
                          "bg-green-900/50 text-green-400 border-green-800 hover:bg-green-900/80",
                        hotel.status == :inactive &&
                          "bg-neutral-800 text-gray-400 border-neutral-700 hover:bg-neutral-700",
                        hotel.active != :active && hotel.status != :inactive &&
                          "bg-amber-900/50 text-amber-400 border-amber-800 hover:bg-amber-900/80"
                      ]}
                      title="Click to toggle status"
                    >
                      {if hotel.active, do: :active, else: :inactive}
                    </button>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-amber-400">
                    {String.duplicate("★", hotel.star_rating || 0)}
                  </td>
                  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6 space-x-2">
                    <.button
                      phx-click="open_edit"
                      phx-value-id={hotel.id}
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
      
    <!-- MAIN HOTEL MODAL -->
      <%= if @show_modal and @form do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md overflow-y-auto py-10">
          <div class="bg-black text-white rounded-2xl shadow-2xl w-full max-w-2xl overflow-hidden border border-neutral-800 my-auto">
            <div class="px-6 py-4 border-b border-neutral-800 flex justify-between items-center bg-black">
              <h3 class="text-lg font-semibold text-white">
                {if @hotel, do: "Edit Hotel", else: "Add New Hotel"}
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
              id="hotel-form"
              phx-change="validate"
              phx-submit="save"
              class="p-6 space-y-6 max-h-[75vh] overflow-y-auto bg-black text-white"
            >
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Hotel Name
                  </label>
                  <.input
                    field={@form[:name]}
                    type="text"
                    placeholder="Grand Plaza Hotel"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>

                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Owner
                  </label>
                  <.input
                    field={@form[:owner_id]}
                    type="select"
                    options={@owners}
                    prompt="Select an owner"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm focus:ring-white focus:border-white"
                  />
                </div>
              </div>
              
    <!-- Hotel Images Preview and Selection Section -->
              <div class="space-y-4">
                <label class="block text-xs font-semibold text-gray-400 uppercase">
                  Hotel Images & Primary Cover
                </label>

                <div class="flex items-start gap-4">
                  <!-- Primary Cover Slot -->
                  <div class="space-y-1">
                    <span class="block text-[10px] text-gray-400 uppercase font-semibold">
                      Primary Cover
                    </span>
                    <% primary_img =
                      Enum.find(@hotel_images, &(&1.id == @primary_image_id)) ||
                        List.first(@hotel_images) %>
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
                      <%= for img <- Enum.reject(@hotel_images, &(&1.id == @primary_image_id)) do %>
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

              <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div class="sm:col-span-2">
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Address Line 1
                  </label>
                  <.input
                    field={@form[:address_line1]}
                    type="text"
                    placeholder="123 Resort Way"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                  />
                </div>
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">City</label>
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
                    Country
                  </label>
                  <.input
                    field={@form[:country]}
                    type="text"
                    placeholder="USA"
                    class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                  />
                </div>
              </div>

              <div class="p-4 bg-black/60 rounded-xl border border-neutral-800 space-y-4">
                <h4 class="text-xs font-bold text-white uppercase tracking-wider">
                  Hotel Operations & Details
                </h4>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                      Front Desk Phone
                    </label>
                    <.input
                      field={@form[:front_desk_phone]}
                      type="text"
                      placeholder="520-555-0199"
                      class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                      Reservation Email
                    </label>
                    <.input
                      field={@form[:reservation_email]}
                      type="email"
                      placeholder="reservations@hotel.com"
                      class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                    />
                  </div>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                  <div>
                    <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                      Check-in
                    </label>
                    <.input
                      field={@form[:check_in_time]}
                      type="time"
                      class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                      Check-out
                    </label>
                    <.input
                      field={@form[:check_out_time]}
                      type="time"
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
                  <div>
                    <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                      Timezone
                    </label>
                    <.input
                      field={@form[:timezone]}
                      type="select"
                      options={@timezones}
                      prompt="Select a timezone"
                      class="w-full rounded-lg bg-black border-neutral-800 text-white text-sm shadow-sm"
                    />
                  </div>
                </div>
                <div>
                  <label class="block text-xs font-semibold text-gray-400 uppercase mb-1">
                    Star Rating
                  </label>
                  <.form_rating field={@form[:star_rating]} max={5} />
                </div>
              </div>

              <div class="flex items-center justify-between pt-4 border-t border-neutral-800">
                <div>
                  <%= if @hotel do %>
                    <.button
                      phx-click="delete"
                      phx-value-id={@hotel.id}
                      class="px-4 py-2 border border-red-900/50 bg-red-950/30 text-red-400 rounded-lg text-sm font-medium hover:bg-red-900/40 cursor-pointer"
                    >
                      Delete Hotel
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
                    Save Hotel
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
                id="hotel-file-picker"
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
