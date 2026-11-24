defmodule AshPhoenixStarterWeb.Plugs.VerifyBillingWebhook do
  @moduledoc """
  Verifies incoming HMAC-SHA256 webhook signatures for Polar (`Standard Webhooks`)
  and Lemon Squeezy (`X-Signature`). Halts with `401 Unauthorized` on invalid signatures.

  ## Usage

      plug AshPhoenixStarterWeb.Plugs.VerifyBillingWebhook, provider: :polar
      plug AshPhoenixStarterWeb.Plugs.VerifyBillingWebhook, provider: :lemonsqueezy
  """

  import Plug.Conn
  alias AshPhoenixStarterWeb.Plugs.CacheRawBodyPlug

  @max_timestamp_skew_sec 300

  def init(opts) do
    Keyword.fetch!(opts, :provider)
  end

  def call(conn, provider) do
    raw_body = CacheRawBodyPlug.get_raw_body(conn)

    if valid_signature?(provider, conn, raw_body) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "Invalid webhook signature"}))
      |> halt()
    end
  end

  # ============================================================================
  # POLAR (STANDARD WEBHOOKS SPEC)
  # ============================================================================

  defp valid_signature?(:polar, conn, raw_body) do
    secret =
      :AshPhoenixStarter
      |> Application.get_env(:polar, [])
      |> Keyword.get(:webhook_secret)

    with true <- is_binary(secret) and secret != "",
         [msg_id] <- get_req_header(conn, "webhook-id"),
         [ts_str] <- get_req_header(conn, "webhook-timestamp"),
         [sig_header] <- get_req_header(conn, "webhook-signature"),
         {ts, ""} <- Integer.parse(ts_str),
         true <- abs(System.system_time(:second) - ts) <= @max_timestamp_skew_sec,
         {:ok, secret_bytes} <- decode_polar_secret(secret) do
      signed_content = "#{msg_id}.#{ts_str}.#{raw_body}"
      expected_b64 = :crypto.mac(:hmac, :sha256, secret_bytes, signed_content) |> Base.encode64()

      sig_header
      |> String.split(" ", trim: true)
      |> Enum.any?(fn
        "v1," <> provided_b64 ->
          byte_size(provided_b64) == byte_size(expected_b64) and
            Plug.Crypto.secure_compare(provided_b64, expected_b64)

        _ ->
          false
      end)
    else
      _ -> false
    end
  end

  # ============================================================================
  # LEMON SQUEEZY (HEX HMAC-SHA256 IN X-SIGNATURE)
  # ============================================================================

  defp valid_signature?(:lemonsqueezy, conn, raw_body) do
    secret =
      :AshPhoenixStarter
      |> Application.get_env(:lemonsqueezy, [])
      |> Keyword.get(:webhook_secret)

    with true <- is_binary(secret) and secret != "",
         [provided_hex] <- get_req_header(conn, "x-signature") do
      expected_hex =
        :crypto.mac(:hmac, :sha256, secret, raw_body)
        |> Base.encode16(case: :lower)

      normalized_provided = String.downcase(String.trim(provided_hex))

      byte_size(normalized_provided) == byte_size(expected_hex) and
        Plug.Crypto.secure_compare(normalized_provided, expected_hex)
    else
      _ -> false
    end
  end

  defp valid_signature?(:gumroad, conn, _raw_body) do
    expected_seller_id =
      :AshPhoenixStarter
      |> Application.get_env(:gumroad, [])
      |> Keyword.get(:seller_id)

    provided = conn.body_params["seller_id"]

    is_binary(expected_seller_id) and expected_seller_id != "" and
      is_binary(provided) and byte_size(provided) == byte_size(expected_seller_id) and
      Plug.Crypto.secure_compare(provided, expected_seller_id)
  end

  defp valid_signature?(:braintree, conn, _raw_body) do
    bt_cfg = Application.get_env(:AshPhoenixStarter, :braintree, [])
    public_key = Keyword.get(bt_cfg, :public_key)
    private_key = Keyword.get(bt_cfg, :private_key)
    sig_param = conn.body_params["bt_signature"]
    payload_param = conn.body_params["bt_payload"]

    with true <- is_binary(public_key) and is_binary(private_key),
         true <- is_binary(sig_param) and is_binary(payload_param),
         matching_sig when is_binary(matching_sig) <- find_braintree_sig(sig_param, public_key) do
      key_hash = :crypto.hash(:sha, private_key)
      expected = :crypto.mac(:hmac, :sha, key_hash, payload_param) |> Base.encode16(case: :lower)

      byte_size(matching_sig) == byte_size(expected) and
        Plug.Crypto.secure_compare(String.downcase(matching_sig), expected)
    else
      _ -> false
    end
  end

  defp find_braintree_sig(sig_param, public_key) do
    sig_param
    |> String.split("&", trim: true)
    |> Enum.find_value(fn pair ->
      case String.split(pair, "|", parts: 2) do
        [^public_key, sig] -> sig
        _ -> nil
      end
    end)
  end

  defp valid_signature?(:paddle, conn, raw_body) do
    secret =
      :AshPhoenixStarter
      |> Application.get_env(:paddle, [])
      |> Keyword.get(:webhook_secret)

    with true <- is_binary(secret) and secret != "",
         [sig_header] <- get_req_header(conn, "paddle-signature"),
         %{"ts" => ts_str, "h1" => provided_hex} <- parse_paddle_sig(sig_header),
         {ts, ""} <- Integer.parse(ts_str),
         true <- abs(System.system_time(:second) - ts) <= @max_timestamp_skew_sec do
      expected_hex =
        :crypto.mac(:hmac, :sha256, secret, "#{ts_str}:#{raw_body}")
        |> Base.encode16(case: :lower)

      normalized_provided = String.downcase(String.trim(provided_hex))

      byte_size(normalized_provided) == byte_size(expected_hex) and
        Plug.Crypto.secure_compare(normalized_provided, expected_hex)
    else
      _ -> false
    end
  end

  defp parse_paddle_sig(header) do
    header
    |> String.split(";", trim: true)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
        _ -> acc
      end
    end)
  end

  defp decode_polar_secret("whsec_" <> b64), do: Base.decode64(b64)
  defp decode_polar_secret(raw), do: {:ok, raw}
end
