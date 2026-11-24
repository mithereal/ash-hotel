defmodule AshPhoenixStarterWeb.MarketLive.Index do
  use AshPhoenixStarterWeb, :live_view

  @impl true
  def mount(socket, _, _) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
  end
end
