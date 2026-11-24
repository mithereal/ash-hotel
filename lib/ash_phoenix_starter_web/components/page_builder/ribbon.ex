defmodule AshPhoenixStarterWeb.Components.PageBuilder.Ribbon do
  use Athanor.Component
  use Phoenix.Component

  @impl Athanor.Component
  def metadata, do: %{type: "ribbon", label: "Ribbon Banner", icon: "fa-bookmark"}

  @impl Athanor.Component
  def fields do
    [
      {"text", :text, label: "Ribbon Text", default: "New Release"},
      {"badge", :text, label: "Ribbon Badge", default: ""},
      {"variant", :select,
       label: "Variant",
       options: ["primary", "secondary", "destructive", "outline"],
       default: "primary"},
      {"position", :select,
       label: "Position", options: ["top-right", "top-left"], default: "top-right"}
    ]
  end

  @impl Athanor.Component
  def render(:live, node, _ctx) do
    assigns = node["props"]

    variant_classes =
      case @variant do
        "secondary" -> "bg-secondary text-secondary-foreground border-secondary"
        "destructive" -> "bg-destructive text-destructive-foreground border-destructive"
        "outline" -> "bg-background text-foreground border-border"
        _ -> "bg-primary text-primary-foreground border-primary"
      end

    position_classes =
      case @position do
        "top-left" -> "top-3 left-3 -rotate-45"
        _ -> "top-3 right-3 rotate-45"
      end

    ~H"""
    <div class="relative overflow-hidden w-full h-full min-h-[120px] rounded-xl border border-border bg-card p-6">
      <div class={"absolute px-3 py-1 text-xs font-semibold uppercase tracking-wider shadow-sm rounded-md border #{variant_classes} #{position_classes}"}>
        {@text}
      </div>
      <div class="flex flex-col justify-center h-full">
        <h4 class="font-semibold text-card-foreground">{@text}</h4>
        <p class="text-sm text-muted-foreground mt-1">{@badge}</p>
      </div>
    </div>
    """
  end
end
