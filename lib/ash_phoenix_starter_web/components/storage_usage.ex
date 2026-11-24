defmodule AshPhoenixStarterWeb.Components.StorageUsageWidget do
  use AshPhoenixStarterWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6 shadow-sm backdrop-blur-sm">
      <!-- Header -->
      <div class="flex items-center justify-between pb-4 border-b border-zinc-800">
        <div>
          <h3 class="text-base font-semibold text-zinc-100">Storage & CDN Usage</h3>
          <p class="text-xs text-zinc-400">
            Current organization storage utilization and active cloud provider
          </p>
        </div>
        <span class={[
          "inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium border",
          provider_badge(@provider),
          "bg-zinc-800 text-zinc-300 border-zinc-700"
        ]}>
          <.core_icon name="hero-cloud" class="w-3.5 h-3.5 mr-1.5" />
          {provider_label(@provider)}
        </span>
      </div>
      
    <!-- Main Usage Stat -->
      <div class="my-6">
        <div class="flex items-baseline justify-between mb-2">
          <span class="text-2xl font-bold tracking-tight text-zinc-100">
            {format_bytes(@used_bytes)}
          </span>
          <span class="text-xs font-medium text-zinc-400">
            Limit: <strong class="text-zinc-200">{format_bytes(@limit_bytes)}</strong>
          </span>
        </div>
        
    <!-- Progress Bar (phia_ui / Tailwind style) -->
        <div class="w-full bg-zinc-800 rounded-full h-2.5 overflow-hidden">
          <div
            class={[
              "h-2.5 rounded-full transition-all duration-500",
              progress_color_class(@usage_percentage)
            ]}
            style={"width: #{@usage_percentage}%"}
          >
          </div>
        </div>
        <div class="flex justify-between items-center mt-1.5 text-xs text-zinc-500">
          <span>{@usage_percentage}% used</span>
          <span>{format_bytes(@limit_bytes - @used_bytes)} remaining</span>
        </div>
      </div>
      
    <!-- Breakdown List -->
      <div class="space-y-3 pt-2 border-t border-zinc-800/60">
        <h4 class="text-xs font-semibold uppercase tracking-wider text-zinc-400">
          Breakdown by type
        </h4>

        <div class="grid grid-cols-2 gap-3 text-sm">
          <div class="flex items-center justify-between p-2.5 rounded-lg bg-zinc-800/40 border border-zinc-800">
            <span class="text-zinc-300 flex items-center text-xs">
              <span class="w-2 h-2 rounded-full bg-blue-400 mr-2"></span> Images
            </span>
            <span class="font-medium text-zinc-200 text-xs">{format_bytes(@breakdown.images)}</span>
          </div>

          <div class="flex items-center justify-between p-2.5 rounded-lg bg-zinc-800/40 border border-zinc-800">
            <span class="text-zinc-300 flex items-center text-xs">
              <span class="w-2 h-2 rounded-full bg-emerald-400 mr-2"></span> Documents
            </span>
            <span class="font-medium text-zinc-200 text-xs">
              {format_bytes(@breakdown.documents)}
            </span>
          </div>

          <div class="flex items-center justify-between p-2.5 rounded-lg bg-zinc-800/40 border border-zinc-800">
            <span class="text-zinc-300 flex items-center text-xs">
              <span class="w-2 h-2 rounded-full bg-purple-400 mr-2"></span> Archives
            </span>
            <span class="font-medium text-zinc-200 text-xs">{format_bytes(@breakdown.archives)}</span>
          </div>

          <div class="flex items-center justify-between p-2.5 rounded-lg bg-zinc-800/40 border border-zinc-800">
            <span class="text-zinc-300 flex items-center text-xs">
              <span class="w-2 h-2 rounded-full bg-zinc-400 mr-2"></span> Other
            </span>
            <span class="font-medium text-zinc-200 text-xs">{format_bytes(@breakdown.other)}</span>
          </div>
        </div>
      </div>
      
    <!-- Footer action if near limit -->
      <%= if @usage_percentage >= 85 do %>
        <div class="mt-4 p-3 rounded-lg bg-amber-500/10 border border-amber-500/20 flex items-center justify-between">
          <div class="flex items-center text-xs text-amber-300">
            <.core_icon name="hero-exclamation-triangle" class="w-4 h-4 mr-2 flex-shrink-0" />
            <span>You are approaching your storage limit.</span>
          </div>
          <.link
            navigate={~p"/settings/billing"}
            class="text-xs font-medium text-amber-400 hover:underline"
          >
            Upgrade &rarr;
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Helpers ---

  defp provider_label("spaces"), do: "DigitalOcean Spaces"
  defp provider_label("r2"), do: "Cloudflare R2"
  defp provider_label("s3"), do: "AWS S3"
  defp provider_label("minio"), do: "MinIO Server"
  defp provider_label(_), do: "Local Disk Storage"

  defp provider_badge("spaces"), do: "bg-blue-500/10 text-blue-400 border-blue-500/20"
  defp provider_badge("r2"), do: "bg-orange-500/10 text-orange-400 border-orange-500/20"
  defp provider_badge("s3"), do: "bg-amber-500/10 text-amber-400 border-amber-500/20"
  defp provider_badge("minio"), do: "bg-purple-500/10 text-purple-400 border-purple-500/20"
  defp provider_badge(_), do: "bg-zinc-500/10 text-zinc-400 border-zinc-500/20"

  defp progress_color_class(pct) when pct >= 90, do: "bg-red-500"
  defp progress_color_class(pct) when pct >= 75, do: "bg-amber-500"
  defp progress_color_class(_), do: "bg-blue-500"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
end
