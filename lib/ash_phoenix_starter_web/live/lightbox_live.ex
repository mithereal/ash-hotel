defmodule AshPhoenixStarterWeb.LightboxViewerLive do
  use AshPhoenixStarterWeb, :live_view

  @impl true
  def mount(%{"path" => path_segments}, _session, socket) do
    file_path = "/" <> Enum.join(path_segments, "/")

    image = %{
      filename: Path.basename(file_path),
      file_url: file_path,
      content_type: "image/" <> (Path.extname(file_path) |> String.trim_leading(".")),
      file_size: nil
    }

    {:ok,
     socket
     |> assign(
       page_title: "Image Viewer",
       image: image,
       zoom: 100,
       rotation: 0,
       show_menu?: false
     )}
  end

  @impl true
  def handle_event("zoom_in", _, socket) do
    {:noreply, assign(socket, zoom: min(socket.assigns.zoom + 25, 300))}
  end

  def handle_event("zoom_out", _, socket) do
    {:noreply, assign(socket, zoom: max(socket.assigns.zoom - 25, 50))}
  end

  def handle_event("reset_transform", _, socket) do
    {:noreply, assign(socket, zoom: 100, rotation: 0)}
  end

  def handle_event("rotate_right", _, socket) do
    {:noreply, assign(socket, rotation: rem(socket.assigns.rotation + 90, 360))}
  end

  def handle_event("toggle_menu", _, socket) do
    {:noreply, assign(socket, show_menu?: !socket.assigns.show_menu?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div uri={@uri}>
      <!-- Centered Maximized Studio Workspace -->
      <div class="fixed inset-x-0 bottom-0 top-0 z-40 bg-neutral-950 flex flex-col select-none overflow-hidden text-white">
        <!-- Top Navigation / Toolbar -->
        <div class="flex items-center justify-between px-6 py-3.5 bg-neutral-900/80 border-b border-neutral-800 backdrop-blur-md z-20">
          <div class="flex items-center space-x-3 truncate">
            <button
              onclick="history.back()"
              class="p-2 rounded-lg bg-black/40 border border-neutral-800 text-gray-400 hover:text-white transition-colors"
              title="Back"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 19l-7-7 7-7"
                />
              </svg>
            </button>
            <span class="text-sm font-semibold text-gray-200 truncate">
              {(@image && @image.filename) || "Image"}
            </span>
          </div>
          
    <!-- Studio Action Controls -->
          <div class="flex items-center space-x-2 relative">
            <button
              type="button"
              phx-click="rotate_right"
              class="p-2 rounded-lg bg-black/40 border border-neutral-800 text-gray-300 hover:text-white hover:bg-neutral-800 transition-colors cursor-pointer"
              title="Rotate 90°"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
            </button>

            <button
              type="button"
              phx-click="zoom_out"
              class="p-2 rounded-lg bg-black/40 border border-neutral-800 text-gray-300 hover:text-white hover:bg-neutral-800 transition-colors cursor-pointer"
              title="Zoom Out"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4" />
              </svg>
            </button>

            <button
              type="button"
              phx-click="reset_transform"
              class="px-2.5 py-1 text-xs font-mono rounded-lg bg-black/40 border border-neutral-800 text-gray-300 hover:text-white hover:bg-neutral-800 transition-colors cursor-pointer"
              title="Reset View"
            >
              {@zoom}%
            </button>

            <button
              type="button"
              phx-click="zoom_in"
              class="p-2 rounded-lg bg-black/40 border border-neutral-800 text-gray-300 hover:text-white hover:bg-neutral-800 transition-colors cursor-pointer"
              title="Zoom In"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 4v16m8-8H4"
                />
              </svg>
            </button>

            <div class="w-px h-5 bg-neutral-800 mx-1"></div>
            
    <!-- Hamburger Dropdown Menu Toggle -->
            <div class="relative">
              <button
                type="button"
                phx-click="toggle_menu"
                class={"p-2 rounded-lg border transition-colors cursor-pointer " <> if(@show_menu?, do: "bg-neutral-800 border-neutral-700 text-white", else: "bg-black/40 border-neutral-800 text-gray-300 hover:text-white hover:bg-neutral-800")}
                title="Properties Menu"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 6h16M4 12h16M4 18h16"
                  />
                </svg>
              </button>
              
    <!-- Dropdown Menu Content -->
              <%= if @show_menu? do %>
                <div class="absolute right-0 mt-2 w-72 bg-neutral-900 border border-neutral-800 rounded-xl shadow-2xl p-4 z-50 text-xs space-y-3">
                  <div class="flex items-center justify-between border-b border-neutral-800 pb-2">
                    <span class="font-semibold uppercase tracking-wider text-gray-400">
                      File Properties
                    </span>
                    <button
                      type="button"
                      phx-click="toggle_menu"
                      class="text-gray-500 hover:text-white"
                    >
                      ✕
                    </button>
                  </div>

                  <div class="space-y-2.5">
                    <div>
                      <span class="text-gray-500 block text-[10px] mb-0.5">File Name</span>
                      <p class="font-medium text-gray-200 truncate bg-neutral-950 p-2 rounded border border-neutral-800">
                        {(@image && @image.filename) || "N/A"}
                      </p>
                    </div>

                    <div>
                      <span class="text-gray-500 block text-[10px] mb-0.5">Content Type</span>
                      <p class="font-medium text-gray-200 bg-neutral-950 p-2 rounded border border-neutral-800">
                        {(@image && @image.content_type) || "image/unknown"}
                      </p>
                    </div>

                    <div>
                      <span class="text-gray-500 block text-[10px] mb-0.5">Direct URL Path</span>
                      <input
                        type="text"
                        readonly
                        value={@image && @image.file_url}
                        class="w-full bg-neutral-950 border border-neutral-800 rounded p-2 text-gray-300 text-[10px]"
                      />
                    </div>
                  </div>

                  <%= if @image && @image.file_url do %>
                    <div class="pt-2 border-t border-neutral-800">
                      <a
                        href={@image.file_url}
                        target="_blank"
                        class="w-full block text-center py-2 bg-white text-black hover:bg-gray-200 font-medium rounded transition-colors"
                      >
                        Open Original in New Tab
                      </a>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Maximized Centered Canvas Workspace -->
        <div class="flex-1 flex items-center justify-center p-8 overflow-auto bg-neutral-950 relative">
          <%= if @image && @image.file_url do %>
            <img
              src={@image.file_url}
              alt={@image.filename}
              class="transition-transform duration-200 ease-out object-contain max-h-[82vh] max-w-[90vw]"
              style={"width: #{@zoom}%; max-width: none; transform: rotate(#{@rotation}deg);"}
            />
          <% else %>
            <div class="flex flex-col items-center justify-center text-gray-500 py-16">
              <svg
                class="w-16 h-16 mb-3 text-neutral-800"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                />
              </svg>
              <p class="text-sm font-medium text-gray-400">No image loaded</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
