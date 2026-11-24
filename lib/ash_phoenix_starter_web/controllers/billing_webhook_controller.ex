defmodule AshPhoenixStarterWeb.BillingWebhookController do
  use AshPhoenixStarterWeb, :controller

  alias AshPhoenixStarter.Billing.Providers.{LemonSqueezy, Polar}

  def polar(conn, params) do
    case Polar.handle_webhook(conn, params) do
      :ok ->
        json(conn, %{received: true})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def lemonsqueezy(conn, params) do
    case LemonSqueezy.handle_webhook(conn, params) do
      :ok ->
        json(conn, %{received: true})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
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
end
