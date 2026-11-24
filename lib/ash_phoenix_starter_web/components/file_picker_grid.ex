defmodule AshPhoenixStarterWeb.Components.FilePickerGridComponent do
  use AshPhoenixStarterWeb, :live_component

  alias AshPhoenixStarter.Uploads.ImageUploader
  alias AshPhoenixStarter.Core.FileAsset

  @chunk_size 100

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:limit, @chunk_size)
     |> allow_upload(:file,
       accept: ~w(.jpg .jpeg .png .gif .webp .pdf .doc .docx .xls .xlsx .txt .zip),
       max_entries: 50,
       max_file_size: 25_000_000
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    tenant =
      socket.assigns[:tenant] ||
        get_in(socket.assigns, [:current_user, :organization, :domain])

    organization_id =
      socket.assigns[:organization_id] ||
        get_in(socket.assigns, [:current_user, :organization, :id])

    type =
      socket.assigns[:type] ||
        get_in(socket.assigns, [:type] || :general)

    {:ok,
     socket
     |> assign(:tenant, tenant)
     |> assign(:organization_id, organization_id)
     |> assign(:type, type)
     |> load_files(tenant)}
  end

  defp load_files(socket, tenant) do
    limit = socket.assigns[:limit] || @chunk_size

    files =
      if tenant,
        do:
          Ash.read!(
            Ash.Query.for_read(FileAsset, :read, %{}, tenant: tenant)
            |> Ash.Query.limit(limit)
          ),
        else: []

    assign(socket, files: files)
  end

  @impl true
  def handle_event("validate", _params, socket) do
    if Enum.any?(socket.assigns.uploads.file.entries, & &1.done?) do
      consume_and_notify(socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_upload", _, socket) do
    consume_and_notify(socket)
  end

  @impl true
  def handle_event("load_more_horizontal", _, socket) do
    new_limit = socket.assigns.limit + @chunk_size
    tenant = socket.assigns.tenant

    {:noreply,
     socket
     |> assign(:limit, new_limit)
     |> load_files(tenant)}
  end

  @impl true
  def handle_event("select_file", %{"id" => id}, socket) do
    file = Enum.find(socket.assigns.files, &(&1.id == id))

    if file do
      send(self(), {:file_selected, file})
    end

    {:noreply, socket}
  end

  defp consume_and_notify(socket) do
    tenant = socket.assigns.tenant
    organization_id = socket.assigns.organization_id
    type = socket.assigns.type || :general

    uploaded_files =
      consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
        scope = %{organization_id: organization_id, type: type}
        file_input = %{filename: entry.client_name, path: path}

        case ImageUploader.store(file_input, scope) do
          {:ok, filename} ->
            url = ImageUploader.url(filename, scope, :original)

            attrs = %{
              filename: entry.client_name,
              content_type: entry.client_type,
              file_size: entry.client_size,
              file_url: url,
              organization_id: organization_id,
              type: type
            }

            file_asset =
              FileAsset
              |> Ash.Changeset.for_create(:create, attrs, tenant: tenant)
              |> Ash.create!()

            {:ok, file_asset}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    # Filter successful uploads
    successes =
      Enum.filter(uploaded_files, fn
        {:ok, _} -> true
        _ -> false
      end)

    case successes do
      [{:ok, first} | _] -> send(self(), {:file_selected, first})
      _ -> nil
    end

    {:noreply, load_files(socket, tenant)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 text-white">
      <!-- Upload Box with Progress Bar -->
      <form
        phx-change="validate"
        phx-submit="save_upload"
        phx-target={@myself}
        class="border-2 border-dashed border-neutral-800 p-4 rounded-xl bg-black/40"
      >
        <label class="block text-xs font-semibold text-gray-400 uppercase mb-2">
          Upload New File
        </label>

        <.live_file_input
          upload={@uploads.file}
          class="block w-full text-sm text-gray-400 file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-xs file:font-semibold file:bg-white file:text-black hover:file:bg-gray-200 cursor-pointer"
        />

        <div class="mt-3 space-y-2">
          <%= for entry <- @uploads.file.entries do %>
            <div class="space-y-1">
              <div class="flex items-center justify-between text-xs text-gray-300">
                <span class="truncate max-w-[200px]">{entry.client_name}</span>
                <span>{entry.progress}%</span>
              </div>
              <div class="w-full bg-neutral-800 h-1.5 rounded-full overflow-hidden">
                <div
                  class="bg-white h-full transition-all duration-150"
                  style={"width: #{entry.progress}%"}
                >
                </div>
              </div>
            </div>
            <%= for err <- upload_errors(@uploads.file, entry) do %>
              <p class="text-xs text-red-500">{error_to_string(err)}</p>
            <% end %>
          <% end %>
        </div>

        <%= if length(@uploads.file.entries) > 0 do %>
          <button class="mt-3 w-full py-2 bg-white text-black font-semibold rounded-lg text-xs hover:bg-gray-200 transition-colors cursor-pointer">
            Confirm & Attach Uploads
          </button>
        <% end %>
      </form>
      
    <!-- Separate Grid Block for Existing Files -->
      <div class="bg-black/40 border border-neutral-800 rounded-xl p-4 sm:p-6">
        <h4 class="text-xs font-semibold text-gray-400 uppercase mb-3">Available Images</h4>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 max-h-[300px] overflow-y-auto pr-1">
          <%= for file <- @files do %>
            <button
              phx-click="select_file"
              phx-value-id={file.id}
              phx-target={@myself}
              class="w-full aspect-square bg-neutral-900 border border-neutral-800 rounded-lg overflow-hidden relative hover:border-white transition-all flex items-center justify-center group cursor-pointer"
            >
              <img
                src={file.file_url}
                class="object-cover w-full h-full group-hover:scale-105 transition-transform"
              />
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 25MB)"
  defp error_to_string(:not_accepted), do: "You selected an unacceptable file type"
  defp error_to_string(:too_many_files), do: "You have selected too many files"
  defp error_to_string(_), do: "An error occurred uploading the file"
end
