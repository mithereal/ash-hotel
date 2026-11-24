defmodule AshPhoenixStarterWeb.Components.PageBuilder.Button do
  use Athanor.Component
  use Phoenix.Component

  @impl Athanor.Component
  def metadata, do: %{type: "button", label: "Button", icon: "fa-square"}

  @impl Athanor.Component
  def fields do
    [
      {"text", :text, label: "Button Text"},
      {"variant", :select,
       label: "Variant",
       options: ["default", "secondary", "outline", "destructive"],
       default: "default"},
      {"size", :select, label: "Size", options: ["sm", "md", "lg"], default: "md"}
    ]
  end

  @impl Athanor.Component
  def render(:live, node, _ctx) do
    assigns = node["props"]

    variant_classes =
      case @variant do
        "secondary" ->
          "bg-secondary text-secondary-foreground hover:bg-secondary/80"

        "outline" ->
          "border border-input bg-background hover:bg-accent hover:text-accent-foreground"

        "destructive" ->
          "bg-destructive text-destructive-foreground hover:bg-destructive/90"

        _ ->
          "bg-primary text-primary-foreground hover:bg-primary/90"
      end

    size_classes =
      case @size do
        "sm" -> "h-8 px-3 text-xs"
        "lg" -> "h-11 px-8 text-base"
        _ -> "h-9 px-4 text-sm"
      end

    ~H"""
    <button class={"inline-flex items-center justify-center rounded-md font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 #{variant_classes} #{size_classes}"}>
      {@text}
    </button>
    """
  end
end
