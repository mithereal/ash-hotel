defmodule AshPhoenixStarterWeb.Components.PageBuilder.Badge do
  use Athanor.Component
  use Phoenix.Component

  @impl Athanor.Component
  def metadata, do: %{type: "badge", label: "Badge", icon: "fa-tag"}

  @impl Athanor.Component
  def fields do
    [
      {"text", :text, label: "Badge Text"},
      {"variant", :select,
       label: "Variant",
       options: ["default", "secondary", "outline", "destructive"],
       default: "default"}
    ]
  end

  @impl Athanor.Component
  def render(:live, node, _ctx) do
    assigns = node["props"]

    variant_classes =
      case @variant do
        "secondary" ->
          "border-transparent bg-secondary text-secondary-foreground hover:bg-secondary/80"

        "outline" ->
          "text-foreground border-border"

        "destructive" ->
          "border-transparent bg-destructive text-destructive-foreground hover:bg-destructive/90"

        _ ->
          "border-transparent bg-primary text-primary-foreground hover:bg-primary/80"
      end

    ~H"""
    <div class={"inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 #{variant_classes}"}>
      {@text}
    </div>
    """
  end
end
