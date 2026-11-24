defmodule AshPhoenixStarterWeb.Components.PageBuilder.Alert do
  use Athanor.Component
  use Phoenix.Component

  @impl Athanor.Component
  def metadata, do: %{type: "alert", label: "Alert", icon: "fa-bell"}

  @impl Athanor.Component
  def fields do
    [
      {"title", :text, label: "Alert Title"},
      {"message", :textarea, label: "Message"},
      {"variant", :select,
       label: "Variant", options: ["default", "destructive"], default: "default"}
    ]
  end

  @impl Athanor.Component
  def render(:live, node, _ctx) do
    assigns = node["props"]

    variant_classes =
      if @variant == "destructive",
        do: "border-destructive/50 text-destructive dark:border-destructive",
        else: "bg-background text-foreground border-border"

    ~H"""
    <div role="alert" class={"relative w-full rounded-lg border p-4 #{variant_classes}"}>
      <h5 class="mb-1 font-medium leading-none tracking-tight">{@title}</h5>
      <div class="text-sm [&_p]:leading-relaxed">{@message}</div>
    </div>
    """
  end
end
