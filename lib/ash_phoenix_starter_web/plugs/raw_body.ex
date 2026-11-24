defmodule AshPhoenixStarterWeb.Plugs.CacheRawBodyPlug do
  @moduledoc """
  Custom body reader for `Plug.Parsers` that preserves the exact unparsed
  request body in `conn.assigns[:raw_body]` for HMAC webhook verification.
  """

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves the complete raw body binary stored on `conn`.
  """
  @spec get_raw_body(Plug.Conn.t()) :: binary()
  def get_raw_body(%Plug.Conn{assigns: %{raw_body: chunks}}) when is_list(chunks) do
    chunks
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  def get_raw_body(_conn), do: ""
end
