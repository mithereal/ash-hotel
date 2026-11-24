defmodule AshPhoenixStarterWeb.Components.PageBuilder.Card do
  use Athanor.Component
  use Phoenix.Component

  @impl Athanor.Component
  def metadata, do: %{type: "card", label: "Card", icon: "fa-id-card"}

  @impl Athanor.Component
  def fields do
    [
      {"title", :text, label: "Card Title"},
      {"description", :textarea, label: "Description"},
      {"content", :textarea, label: "Card Content"}
    ]
  end

  @impl Athanor.Component
  def render(:live, node, _ctx) do
    assigns = node["props"]

    ~H"""
    <div class="rounded-xl border bg-card text-card-foreground shadow">
      <div class="flex flex-col space-y-1.5 p-6">
        <h3 class="font-semibold leading-none tracking-tight">{@title}</h3>
        <p class="text-sm text-muted-foreground">{@description}</p>
      </div>
      <div class="p-6 pt-0">
        <p>{@content}</p>
      </div>
    </div>
    """
  end
end
