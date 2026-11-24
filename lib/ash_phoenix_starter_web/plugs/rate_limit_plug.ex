defmodule HotelWeb.Plugs.RateLimitPlug do
  @moduledoc """
  ETS-backed fixed-window rate limiter for public QR checkout, webhook,
  camera ingest, and MPP endpoints.
  """
  import Plug.Conn

  @table :hotel_rate_limits

  def init(opts) do
    ensure_table()

    %{
      limit: Keyword.get(opts, :limit, 60),
      window_seconds: Keyword.get(opts, :window_seconds, 60),
      bucket_prefix: Keyword.get(opts, :bucket, "default")
    }
  end

  def call(conn, %{limit: limit, window_seconds: window, bucket_prefix: prefix}) do
    ensure_table()
    ip_str = conn.remote_ip |> :inet.ntoa() |> to_string()
    window_slot = div(System.system_time(:second), window)
    key = {prefix, ip_str, window_slot}

    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    if count <= limit do
      conn
      |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
      |> put_resp_header("x-ratelimit-remaining", Integer.to_string(max(limit - count, 0)))
    else
      conn
      |> put_resp_header("retry-after", Integer.to_string(window))
      |> put_status(429)
      |> Phoenix.Controller.json(%{error: "rate_limit_exceeded"})
      |> halt()
    end
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, write_concurrency: true])
    end
  rescue
    ArgumentError -> :ok
  end
end
