defmodule AshPhoenixStarterWeb.Components.PageBuilder.Table do
  use Athanor.Component
  use Phoenix.Component

  @impl Athanor.Component
  def metadata, do: %{type: "table", label: "Table", icon: "fa-table"}

  @impl Athanor.Component
  def fields do
    [
      {"headers", :text, label: "Headers (Comma separated)", default: "Name, Email, Role"},
      {"rows", :textarea, label: "Rows Data (JSON array of arrays or objects)"}
    ]
  end

  @impl Athanor.Component
  def render(:live, node, _ctx) do
    assigns = node["props"]

    headers = String.split(@headers || "", ",") |> Enum.map(&String.trim/1)

    # Safely decode the JSON string into Elixir lists/maps
    rows =
      case Jason.decode(@rows || "[]") do
        {:ok, parsed} when is_list(parsed) -> parsed
        _ -> []
      end

    assigns = assign(assigns, headers: headers, rows: rows)

    ~H"""
    <div class="relative w-full overflow-auto rounded-md border border-border bg-card">
      <table class="w-full caption-bottom text-sm">
        <thead class="[&_tr]:border-b border-border">
          <tr class="border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted">
            <th
              :for={header <- @headers}
              class="h-12 px-4 text-left align-middle font-medium text-muted-foreground"
            >
              {header}
            </th>
          </tr>
        </thead>
        <tbody class="[&_tr:last-child]:border-0">
          <tr
            :for={row <- @rows}
            class="border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted"
          >
            <td
              :for={cell <- if is_map(row), do: Map.values(row), else: row}
              class="p-4 align-middle text-foreground"
            >
              {cell}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
