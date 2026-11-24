defmodule AshPhoenixStarterWeb.HotelMediaLive do
  use AshPhoenixStarterWeb, :live_view

  alias AshPhoenixStarter.Billing.UsageTracker
  alias AshPhoenixStarter.Uploads.{ImageUploader, StorageDispatcher}
  alias AshPhoenixStarter.Uploads.Workers.GenerateThumbnailWorker

  alias AshPhoenixStarter.Core.FileAsset
  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_organization.id
    region_id = socket.assigns[:current_region_id] || "global"

    socket =
      socket
      |> assign(:organization_id, org_id)
      |> assign(:region_id, region_id)
      |> assign(:quota_exceeded?, UsageTracker.bandwidth_exceeded?(region_id, org_id))
      |> assign(:photos, load_hotel_photos(org_id))
      |> allow_upload(:hotel_photos,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 10,
        max_file_size: 25_000_000,
        external: &presign_upload/2
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :hotel_photos, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    org_id = socket.assigns.organization_id
    region_id = socket.assigns.region_id

    uploaded_files =
      consume_uploaded_entries(socket, :hotel_photos, fn _meta, entry ->
        scope = %{type: :hotel_photo, region_id: region_id, organization_id: org_id}
        file_url = ImageUploader.url(entry.client_name, scope, :original)

        {:ok, asset} =
          FileAsset.create(
            %{
              filename: Path.basename(entry.client_name),
              file_url: file_url,
              file_size: entry.client_size,
              content_type: entry.client_type,
              organization_id: org_id,
              region_id: region_id,
              type: :hotel_photo
            },
            authorize?: false
          )

        %{
          "file_asset_id" => asset.id,
          "file_name" => asset.filename,
          "organization_id" => org_id,
          "region_id" => region_id,
          "type" => "hotel_photo"
        }
        |> GenerateThumbnailWorker.new()
        |> Oban.insert()

        {:ok, asset}
      end)

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Uploaded #{length(uploaded_files)} photo(s). Generating WebP previews..."
     )
     |> assign(:photos, load_hotel_photos(org_id))}
  end

  defp photo_url(%FileAsset{} = asset, region_id, org_id, quota_exceeded?) do
    scope = %{type: asset.type, region_id: region_id, organization_id: org_id}

    ImageUploader.url(asset.filename, scope, :original,
      quota_exceeded?: quota_exceeded?,
      known_bytes: if(quota_exceeded?, do: asset.thumb_size || 0, else: asset.file_size || 0)
    )
  end

  defp load_hotel_photos(org_id) do
    FileAsset
    |> Ash.Query.filter(organization_id == ^org_id and type == :hotel_photo)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp presign_upload(entry, socket) do
    scope = %{
      type: :hotel_photo,
      region_id: socket.assigns.region_id,
      organization_id: socket.assigns.organization_id
    }

    key = ImageUploader.object_key(:original, entry.client_name, scope)

    with {:ok, _size} <-
           ImageUploader.validate(%{file_name: entry.client_name, size: entry.client_size}, scope),
         {:ok, url} <-
           StorageDispatcher.presigned_put_url(key, scope, content_type: entry.client_type) do
      {:ok, %{uploader: "S3", key: key, url: url}, socket}
    else
      {:error, reason} -> {:error, reason, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6 space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Property Gallery</h1>

          <p class="text-sm text-gray-500">Region: {@region_id}</p>
        </div>

        <span class={[
          "px-3 py-1 rounded-full text-xs font-medium",
          if(@quota_exceeded?,
            do: "bg-amber-100 text-amber-800",
            else: "bg-emerald-100 text-emerald-800"
          )
        ]}>
          {if @quota_exceeded?,
            do: "Bandwidth Cap Reached (Serving Optimized Previews)",
            else: "Within Monthly Bandwidth"}
        </span>
      </div>

      <form id="hotel-upload-form" phx-submit="save" phx-change="validate" class="space-y-4">
        <div
          phx-drop-target={@uploads.hotel_photos.ref}
          class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-indigo-500 transition"
        >
          <.live_file_input upload={@uploads.hotel_photos} class="block mx-auto" />
          <p class="mt-2 text-xs text-gray-500">
            JPG, PNG, or WebP up to 25MB each (Direct-to-Cloud Upload)
          </p>
        </div>

        <%= for entry <- @uploads.hotel_photos.entries do %>
          <div class="flex items-center justify-between bg-gray-50 p-3 rounded border">
            <div class="flex items-center gap-3 w-2/3">
              <.live_img_preview entry={entry} class="w-12 h-12 object-cover rounded" />
              <div class="w-full">
                <p class="text-sm font-medium truncate">{entry.client_name}</p>

                <div class="w-full bg-gray-200 rounded-full h-2 mt-1">
                  <div class="bg-indigo-600 h-2 rounded-full" style={"width: #{entry.progress}%"}>
                  </div>
                </div>
              </div>
            </div>

            <button
              type="button"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              class="text-xs text-red-600 hover:underline"
            >
              Cancel
            </button>
          </div>

          <%= for err <- upload_errors(@uploads.hotel_photos, entry) do %>
            <p class="text-xs text-red-600">{error_to_string(err)}</p>
          <% end %>
        <% end %>

        <%= if @uploads.hotel_photos.entries != [] do %>
          <button
            type="submit"
            class="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded hover:bg-indigo-700"
          >
            Save Uploaded Photos
          </button>
        <% end %>
      </form>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 pt-4">
        <%= for photo <- @photos do %>
          <div class="rounded overflow-hidden border bg-white">
            <img
              src={photo_url(photo, @region_id, @organization_id, @quota_exceeded?)}
              alt={photo.file_name}
              class="w-full h-40 object-cover"
              loading="lazy"
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp photo_url(photo, region_id, org_id, quota_exceeded?) do
    scope = %{type: :hotel_photo, region_id: region_id, organization_id: org_id}

    ImageUploader.url(photo.file_name, scope, :original,
      quota_exceeded?: quota_exceeded?,
      known_bytes: if(quota_exceeded?, do: photo.thumb_bytes, else: photo.original_bytes)
    )
  end

  defp error_to_string(:too_large), do: "File exceeds the 25MB limit."
  defp error_to_string(:too_many_files), do: "Maximum 10 files per batch."
  defp error_to_string(:not_accepted), do: "Only JPG, PNG, and WebP files are allowed."

  defp error_to_string(:storage_quota_exceeded),
    do: "Monthly storage quota exceeded. Upgrade your plan to upload more."

  defp error_to_string(err), do: "Upload error: #{inspect(err)}"
end
