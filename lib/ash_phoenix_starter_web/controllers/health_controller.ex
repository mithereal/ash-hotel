defmodule AshPhoenixStarterWeb.HealthController do
  use AshPhoenixStarterWeb, :controller

  def check(conn, _params) do
    db_ok? = match?({:ok, _}, Ecto.Adapters.SQL.query(Hotel.Repo, "SELECT 1", []))
    oban_ok? = is_pid(Oban.Registry.whereis(Oban))
    registry_ok? = :ets.whereis(:hotel_payment_providers) != :undefined

    if db_ok? and oban_ok? and registry_ok? do
      json(conn, %{
        status: "ok",
        node: node(),
        db: "connected",
        oban: "running",
        registries: "ready"
      })
    else
      conn
      |> put_status(503)
      |> json(%{
        status: "degraded",
        db: db_ok?,
        oban: oban_ok?,
        registries: registry_ok?
      })
    end
  end
end
