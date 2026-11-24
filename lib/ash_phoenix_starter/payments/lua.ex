defmodule Hotel.Payments.Lua.Sandbox do
  @moduledoc """
  Executes sandboxed Lua 5.3 payment provider scripts inside Luerl with
  stripped OS/IO globals, reduction limits, and safe Elixir host bridges.
  """

  @max_reductions 100_000
  @allowed_url_prefixes ["https://"]

  @doc """
  Initializes a clean Luerl VM state, strips unsafe stdlib tables,
  injects host bridge functions, and evaluates the provider Lua script.
  """
  def init_vm(lua_source) when is_binary(lua_source) do
    vm =
      :luerl.init()
      |> strip_unsafe_globals()
      |> inject_host_bridges()

    case :luerl.do(lua_source, vm) do
      {:ok, _res, new_vm} -> {:ok, new_vm}
      {:lua_error, reason, _vm} -> {:error, {:lua_syntax_or_runtime_error, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Calls a global Lua function inside the initialized VM with a strict reduction limit.
  """
  def call(vm, func_name, args \\ []) when is_binary(func_name) do
    encoded_args = Enum.map(args, &to_lua_term/1)

    case :luerl.call_function([func_name], encoded_args, vm, max_reductions: @max_reductions) do
      {:ok, [result | _], _new_vm} ->
        {:ok, from_lua_term(result)}

      {:ok, [], _new_vm} ->
        {:ok, nil}

      {:lua_error, reason, _vm} ->
        {:error, {:lua_execution_error, reason}}

      {:error, :reductions} ->
        {:error, :lua_cpu_limit_exceeded}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp strip_unsafe_globals(vm) do
    Enum.reduce(["os", "io", "package", "debug", "dofile", "loadfile"], vm, fn global, acc ->
      :luerl.set_table([global], nil, acc)
    end)
  end

  defp inject_host_bridges(vm) do
    host_table = [
      {"http_request", &host_http_request/2},
      {"hmac_sha256_hex", &host_hmac_sha256_hex/2},
      {"hmac_sha256_base64", &host_hmac_sha256_base64/2},
      {"base64_encode", &host_base64_encode/2},
      {"json_encode", &host_json_encode/2},
      {"json_decode", &host_json_decode/2},
      {"secure_compare", &host_secure_compare/2}
    ]

    :luerl.set_table(["host"], host_table, vm)
  end

  # --- Elixir Host Functions Exposed to Lua as `host.*` ---

  defp host_http_request([req_table], vm) do
    req = from_lua_term(req_table)
    url = Map.get(req, "url", "")

    if Enum.any?(@allowed_url_prefixes, &String.starts_with?(url, &1)) do
      method = req |> Map.get("method", "POST") |> String.downcase() |> String.to_existing_atom()
      headers = Map.get(req, "headers", %{}) |> Map.to_list()
      body = Map.get(req, "body")

      case Req.request(
             method: method,
             url: url,
             headers: headers,
             body: body,
             receive_timeout: 15_000,
             retry: :transient,
             max_retries: 2
           ) do
        {:ok, %{status: status, body: resp_body}} ->
          encoded_body = if is_binary(resp_body), do: resp_body, else: Jason.encode!(resp_body)
          {[to_lua_term(%{"status" => status, "body" => encoded_body})], vm}

        {:error, reason} ->
          {[to_lua_term(%{"status" => 0, "error" => inspect(reason)})], vm}
      end
    else
      {[to_lua_term(%{"status" => 0, "error" => "Only HTTPS URLs are permitted"})], vm}
    end
  end

  defp host_hmac_sha256_hex([secret, payload], vm) do
    hex = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
    {[hex], vm}
  end

  defp host_hmac_sha256_base64([secret, payload], vm) do
    b64 = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode64()
    {[b64], vm}
  end

  defp host_base64_encode([input], vm) do
    {[Base.encode64(input)], vm}
  end

  defp host_json_encode([lua_val], vm) do
    {[Jason.encode!(from_lua_term(lua_val))], vm}
  end

  defp host_json_decode([json_str], vm) do
    case Jason.decode(json_str) do
      {:ok, map} -> {[to_lua_term(map)], vm}
      {:error, _} -> {[nil], vm}
    end
  end

  defp host_secure_compare([a, b], vm) when is_binary(a) and is_binary(b) do
    {[Plug.Crypto.secure_compare(a, b)], vm}
  end

  defp host_secure_compare(_, vm), do: {[false], vm}

  # --- Elixir <-> Luerl Term Conversion ---

  def to_lua_term(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {to_string(k), to_lua_term(v)} end)
  end

  def to_lua_term(list) when is_list(list) do
    list |> Enum.with_index(1) |> Enum.map(fn {v, idx} -> {idx, to_lua_term(v)} end)
  end

  def to_lua_term(atom) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end

  def to_lua_term(val), do: val

  def from_lua_term(list) when is_list(list) do
    if Enum.all?(list, fn {k, _v} -> is_integer(k) end) do
      list |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {_k, v} -> from_lua_term(v) end)
    else
      Map.new(list, fn {k, v} -> {to_string(k), from_lua_term(v)} end)
    end
  end

  def from_lua_term(val), do: val
end

defmodule Hotel.Payments.Lua.Adapter do
  @moduledoc """
  Bridges the Hotel.Payments.Provider contract to a sandboxed Lua script.
  """
  alias Hotel.Payments.Lua.Sandbox

  def validate_and_extract_metadata(lua_source) do
    with {:ok, vm} <- Sandbox.init_vm(lua_source),
         {:ok, raw_meta} when is_map(raw_meta) <- Sandbox.call(vm, "metadata", []) do
      meta = %{
        id: Map.fetch!(raw_meta, "id"),
        name: Map.fetch!(raw_meta, "name"),
        regions: Map.get(raw_meta, "regions", ["GLOBAL"]),
        currencies: Map.get(raw_meta, "currencies", ["USD"]),
        supports_holds?: Map.get(raw_meta, "supports_holds", false),
        runtime: :lua
      }

      {:ok, meta}
    else
      _ -> {:error, :invalid_lua_provider_metadata}
    end
  end

  def authorize(lua_source, amount_cents, currency, opts) do
    opts_map =
      opts
      |> Keyword.delete(:config)
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    config = Keyword.fetch!(opts, :config)

    with {:ok, vm} <- Sandbox.init_vm(lua_source),
         {:ok, %{"ok" => true} = res} <-
           Sandbox.call(vm, "authorize", [amount_cents, currency, config, opts_map]) do
      status =
        case res["status"] do
          "captured" -> :captured
          "pending" -> :pending
          _ -> :authorized
        end

      {:ok,
       %{
         transaction_id: Map.fetch!(res, "transaction_id"),
         status: status,
         redirect_url: res["redirect_url"],
         raw_response: res["raw_response"] || %{}
       }}
    else
      {:ok, %{"ok" => false, "error" => err}} -> {:error, {:lua_provider_error, err}}
      {:error, reason} -> {:error, reason}
    end
  end

  def capture(lua_source, transaction_id, opts) do
    config = Keyword.fetch!(opts, :config)
    opts_map = opts |> Keyword.delete(:config) |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    with {:ok, vm} <- Sandbox.init_vm(lua_source),
         {:ok, %{"ok" => true} = res} <-
           Sandbox.call(vm, "capture", [transaction_id, config, opts_map]) do
      {:ok,
       %{
         transaction_id: res["transaction_id"] || transaction_id,
         status: :captured,
         raw_response: res["raw_response"] || %{}
       }}
    else
      {:ok, %{"ok" => false, "error" => err}} -> {:error, {:lua_provider_error, err}}
      {:error, reason} -> {:error, reason}
    end
  end

  def void(lua_source, transaction_id, opts) do
    config = Keyword.fetch!(opts, :config)
    opts_map = opts |> Keyword.delete(:config) |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    with {:ok, vm} <- Sandbox.init_vm(lua_source),
         {:ok, %{"ok" => true} = res} <-
           Sandbox.call(vm, "void", [transaction_id, config, opts_map]) do
      {:ok,
       %{
         transaction_id: res["transaction_id"] || transaction_id,
         status: :failed,
         raw_response: res["raw_response"] || %{}
       }}
    else
      {:ok, %{"ok" => false, "error" => err}} -> {:error, {:lua_provider_error, err}}
      {:error, reason} -> {:error, reason}
    end
  end

  def refund(lua_source, transaction_id, amount_cents, opts) do
    config = Keyword.fetch!(opts, :config)
    opts_map = opts |> Keyword.delete(:config) |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    with {:ok, vm} <- Sandbox.init_vm(lua_source),
         {:ok, %{"ok" => true} = res} <-
           Sandbox.call(vm, "refund", [transaction_id, amount_cents, config, opts_map]) do
      {:ok,
       %{
         transaction_id: res["transaction_id"] || transaction_id,
         status: :captured,
         raw_response: res["raw_response"] || %{}
       }}
    else
      {:ok, %{"ok" => false, "error" => err}} -> {:error, {:lua_provider_error, err}}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_webhook(lua_source, raw_body, headers, config) do
    with {:ok, vm} <- Sandbox.init_vm(lua_source),
         {:ok, %{"ok" => true} = res} <-
           Sandbox.call(vm, "handle_webhook", [raw_body, headers, config]) do
      event =
        case res["event"] do
          "payment_authorized" -> :payment_authorized
          "payment_captured" -> :payment_captured
          "payment_voided" -> :payment_voided
          "payment_refunded" -> :payment_refunded
          "payment_failed" -> :payment_failed
          _ -> :unhandled
        end

      {:ok, %{event: event, transaction_id: res["transaction_id"], raw: res["raw"] || %{}}}
    else
      {:ok, %{"ok" => false, "error" => err}} -> {:error, {:lua_webhook_error, err}}
      {:error, reason} -> {:error, reason}
    end
  end
end
