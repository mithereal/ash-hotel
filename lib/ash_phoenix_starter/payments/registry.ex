defmodule AshPhoenixStarter.Payments.Registry do
  use GenServer
  alias Hotel.Payments.Lua.Adapter, as: LuaAdapter

  @table :hotel_payment_providers

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    Application.get_env(:hotel, :payment_providers, []) |> Enum.each(&register_beam_module/1)
    {:ok, %{}}
  end

  def register_beam_module(module) when is_atom(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :metadata, 0) do
      meta = Map.put(module.metadata(), :runtime, :beam)
      :ets.insert(@table, {meta.id, {:beam, module}, meta})
      {:ok, meta}
    else
      _ -> {:error, :invalid_provider_module}
    end
  end

  def register_lua_script(lua_source) when is_binary(lua_source) do
    with {:ok, meta} <- LuaAdapter.validate_and_extract_metadata(lua_source) do
      :ets.insert(@table, {meta.id, {:lua, lua_source}, meta})
      {:ok, meta}
    end
  end

  def fetch(provider_id) when is_binary(provider_id) do
    case :ets.lookup(@table, provider_id) do
      [{^provider_id, handler, _meta}] -> {:ok, handler}
      [] -> {:error, :provider_not_found}
    end
  end

  # Unified execution helpers used by DispatchProvider & WebhookController
  def invoke_authorize({:beam, mod}, cents, curr, opts), do: mod.authorize(cents, curr, opts)
  def invoke_authorize({:lua, src}, cents, curr, opts), do: LuaAdapter.authorize(src, cents, curr, opts)

  def invoke_capture({:beam, mod}, tx_id, opts), do: mod.capture(tx_id, opts)
  def invoke_capture({:lua, src}, tx_id, opts), do: LuaAdapter.capture(src, tx_id, opts)

  def invoke_void({:beam, mod}, tx_id, opts), do: mod.void(tx_id, opts)
  def invoke_void({:lua, src}, tx_id, opts), do: LuaAdapter.void(src, tx_id, opts)

  def invoke_refund({:beam, mod}, tx_id, cents, opts), do: mod.refund(tx_id, cents, opts)
  def invoke_refund({:lua, src}, tx_id, cents, opts), do: LuaAdapter.refund(src, tx_id, cents, opts)

  def invoke_webhook({:beam, mod}, raw, headers, cfg), do: mod.handle_webhook(raw, headers, cfg)
  def invoke_webhook({:lua, src}, raw, headers, cfg), do: LuaAdapter.handle_webhook(src, raw, headers, cfg)
end


function authorize(amount_cents, currency, config, opts)
  local auth_header = "Basic " .. host.base64_encode(config.private_key .. ":")
  local payload = host.json_encode({
    currency = currency,
    pre_authorize = true,
    customer_info = {
      name = opts.customer_name or "Hotel Guest",
      email = opts.customer_email,
      phone = opts.customer_phone
    },
    line_items = {
      { name = opts.description or "Room Reservation", unit_price = amount_cents, quantity = 1 }
    },
    charges = {
      {
        payment_method = {
          type = opts.payment_method or "card",
          token_id = opts.token_id
        }
      }
    }
  })

  local resp = host.http_request({
    method = "POST",
    url = "https://conekta.io",
    headers = {
      ["Authorization"] = auth_header,
      ["Accept"] = "application/vnd.conekta-v2.1.0+json",
      ["Content-Type"] = "application/json",
      ["X-Idempotency-Key"] = opts.idempotency_key
    },
    body = payload
  })

  if resp.status >= 200 and resp.status < 300 then
    local data = host.json_decode(resp.body)
    return {
      ok = true,
      transaction_id = data.id,
      status = "authorized",
      raw_response = data
    }
  else
    return { ok = false, error = resp.body or resp.error }
  end
end

function capture(transaction_id, config, opts)
  local auth_header = "Basic " .. host.base64_encode(config.private_key .. ":")
  local resp = host.http_request({
    method = "POST",
    url = "https://conekta.io/" .. transaction_id .. "/capture",
    headers = {
      ["Authorization"] = auth_header,
      ["Accept"] = "application/vnd.conekta-v2.1.0+json",
      ["Content-Type"] = "application/json"
    },
    body = "{}"
  })

  if resp.status >= 200 and resp.status < 300 then
    return { ok = true, transaction_id = transaction_id, raw_response = host.json_decode(resp.body) }
  else
    return { ok = false, error = resp.body }
  end
end

function void(transaction_id, config, opts)
  local auth_header = "Basic " .. host.base64_encode(config.private_key .. ":")
  local resp = host.http_request({
    method = "POST",
    url = "https://conekta.io/" .. transaction_id .. "/void",
    headers = {
      ["Authorization"] = auth_header,
      ["Accept"] = "application/vnd.conekta-v2.1.0+json"
    },
    body = "{}"
  })

  if resp.status >= 200 and resp.status < 300 then
    return { ok = true, transaction_id = transaction_id, raw_response = host.json_decode(resp.body) }
  else
    return { ok = false, error = resp.body }
  end
end

function refund(transaction_id, amount_cents, config, opts)
  local auth_header = "Basic " .. host.base64_encode(config.private_key .. ":")
  local body = host.json_encode({ amount = amount_cents, reason = opts.reason or "requested_by_client" })
  local resp = host.http_request({
    method = "POST",
    url = "https://conekta.io/" .. transaction_id .. "/refunds",
    headers = {
      ["Authorization"] = auth_header,
      ["Accept"] = "application/vnd.conekta-v2.1.0+json",
      ["Content-Type"] = "application/json"
    },
    body = body
  })

  if resp.status >= 200 and resp.status < 300 then
    return { ok = true, transaction_id = transaction_id, raw_response = host.json_decode(resp.body) }
  else
    return { ok = false, error = resp.body }
  end
end

function handle_webhook(raw_body, headers, config)
  local sig = headers["digest"] or ""
  local expected = host.hmac_sha256_base64(config.webhook_secret, raw_body)

  if not host.secure_compare(sig, expected) then
    return { ok = false, error = "Invalid Conekta webhook signature" }
  end

  local payload = host.json_decode(raw_body)
  local event_map = {
    ["order.paid"] = "payment_captured",
    ["order.pre_authorized"] = "payment_authorized",
    ["order.voided"] = "payment_voided",
    ["order.refunded"] = "payment_refunded"
  }

  return {
    ok = true,
    event = event_map[payload.type] or "unhandled",
    transaction_id = payload.data.object.id,
    raw = payload
  }
end