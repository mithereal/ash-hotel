defmodule AshPhoenixStarterWeb.Components.PageBuilder.Hero do
  use Athanor.Component
  use Phoenix.Component

  @impl Athanor.Component
  def metadata, do: %{type: "hero", label: "Hero", icon: "fa-image"}

  @impl Athanor.Component
  def fields do
    [
      {"title", :text, label: "Title"},
      {"subtitle", :textarea, label: "Subtitle"}
    ]
  end

  @impl Athanor.Component
  def render(:live, node, _ctx) do
    IO.inspect(node, label: "node")
    assigns = node["props"]

    ~H"""
    <section class="py-24 text-center">
      <h1 class="text-5xl font-bold">{@title}</h1>
      <p class="mt-4 text-lg">{@subtitle}</p>
    </section>
    """
  end
end
