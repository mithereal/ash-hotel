defmodule AshPhoenixStarterWeb.Pages.EditorLive do
  use Athanor.Editor.Live, registry: :page_builder
  alias AshPhoenixStarter.Core.Page

  @impl Athanor.Editor
  def load(%{"id" => id}, session, socket) do
    tenant = socket.assigns[:current_user].team.domain
    {status, page} = Page.get_page_by_slug!(id, tenant: tenant)

    {:ok,
     %{
       content: page.editor_content || %{"content" => []},
       metadata: %{page_title: "Editing #{page.name}", page: page},
       ctx: %{}
     }}
  end

  @impl Athanor.Editor
  def save(socket, %{content: content}) do
    tenant = socket.assigns[:current_user].team.domain

    socket.assigns.metadata.page
    |> Ash.Changeset.for_update(:update, %{editor_content: content}, tenant: tenant)
    |> Ash.update(tenant: tenant)
  end
end
