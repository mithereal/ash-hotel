defmodule AshPhoenixStarterWeb.AdminSearchLive do
  use AshPhoenixStarterWeb, :live_view

  on_mount {AshPhoenixStarterWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(params, _session, socket) do
    hoa = Map.get(params, "hoa", "")
    entity = Map.get(params, "entity", "")
    query = Map.get(params, "query", "")

    # Execute search if a query or filters are present
    results =
      if query != "" || hoa != "" || entity != "",
        do: perform_search(hoa, entity, query),
        else: nil

    {:ok,
     assign(socket,
       search_results: results,
       selected_hoa: hoa,
       selected_entity: entity,
       search_query: query
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Keeps it reactive if user updates search via live navigation later
    hoa = Map.get(params, "hoa", "")
    entity = Map.get(params, "entity", "")
    query = Map.get(params, "query", "")

    results =
      if query != "" || hoa != "" || entity != "",
        do: perform_search(hoa, entity, query),
        else: nil

    {:noreply,
     assign(socket,
       search_results: results,
       selected_hoa: hoa,
       selected_entity: entity,
       search_query: query
     )}
  end

  defp perform_search(hoa, entity, query) do
    [
      %{
        id: 1,
        title: "Result for #{entity} (HOA: #{hoa})",
        details: "Matched query: '#{query}'"
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} uri={@uri}>
      <div class="p-6 space-y-6">
        <div class="bg-black shadow-sm shadow-[0_0_15px_rgba(255,255,255,0.15)] p-6 mb-4 text-white">
          <h2 class="text-lg font-bold mb-4">Search Results for "{@search_query}"</h2>

          <%= if @search_results do %>
            <ul class="divide-y divide-white/10">
              <%= for result <- @search_results do %>
                <li class="py-2">
                  <p class="font-medium">{result.title}</p>
                  <p class="text-xs text-gray-400">{result.details}</p>
                </li>
              <% end %>
            </ul>
          <% else %>
            <p class="text-gray-400">No search parameters provided.</p>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
