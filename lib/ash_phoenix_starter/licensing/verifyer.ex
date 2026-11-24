defmodule AshPhoenixStarter.Licensing.Verifier do
  @moduledoc """
  Hardened Ed25519 license key verifier.
  Strictly enforces cryptographic signatures, mandatory integer `exp` timestamps,
  valid tiers, and optional email/domain bindings.
  """

  @default_public_key_b64 "NaX6VOxGMCQhcGD/3klkWxNqOLWmRMZlpa33fPjgy7g="
  @clock_skew_seconds 60
  @valid_tiers ~w(basic plus pro enterprise)

  @type claims :: %{
          tenant_id: String.t() | nil,
          domain: String.t() | nil,
          email: String.t() | nil,
          tier: String.t(),
          iat: integer() | nil,
          exp: integer()
        }

  @spec verify(String.t() | nil, keyword()) :: {:ok, claims()} | {:error, atom()}
  def verify(license_key, opts \\ [])

  def verify(license_key, opts) when is_binary(license_key) and license_key != "" do
    with [payload_b64, sig_b64] <- String.split(String.trim(license_key), ".", parts: 2),
         {:ok, sig_bytes} <- Base.url_decode64(sig_b64, padding: false),
         {:ok, pub_key_bytes} <- decode_public_key(opts),
         true <- verify_ed25519(payload_b64, sig_bytes, pub_key_bytes),
         {:ok, payload_json} <- Base.url_decode64(payload_b64, padding: false),
         {:ok, raw_claims} when is_map(raw_claims) <- Jason.decode(payload_json),
         :ok <- validate_tier(raw_claims["tier"]),
         :ok <- validate_iat(raw_claims["iat"]),
         {:ok, exp_sec} <- validate_exp(raw_claims["exp"]),
         :ok <- check_domain(raw_claims["domain"], Keyword.get(opts, :expected_domain)),
         :ok <- check_email(raw_claims["email"], Keyword.get(opts, :expected_email)) do
      {:ok,
       %{
         tenant_id: raw_claims["tenant_id"],
         domain: raw_claims["domain"],
         email: raw_claims["email"],
         tier: raw_claims["tier"],
         iat: raw_claims["iat"],
         exp: exp_sec
       }}
    else
      false -> {:error, :invalid_signature}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed_license}
    end
  end

  def verify(_, _opts), do: {:error, :missing_license}

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp verify_ed25519(message, signature, public_key)
       when byte_size(signature) == 64 and byte_size(public_key) == 32 do
    :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
  end

  defp verify_ed25519(_message, _signature, _public_key), do: false

  defp decode_public_key(opts) do
    b64 =
      Keyword.get(opts, :public_key) ||
        Application.get_env(:AshPhoenixStarter, :license_public_key) ||
        @default_public_key_b64

    case Base.decode64(String.trim(b64)) do
      {:ok, key} when byte_size(key) == 32 -> {:ok, key}
      _ -> {:error, :invalid_public_key}
    end
  end

  defp validate_tier(tier) when is_binary(tier) do
    if String.downcase(String.trim(tier)) in @valid_tiers, do: :ok, else: {:error, :invalid_tier}
  end

  defp validate_tier(_), do: {:error, :missing_tier}

  defp validate_iat(nil), do: :ok

  defp validate_iat(iat) when is_integer(iat) and iat > 0 do
    if iat <= System.system_time(:second) + @clock_skew_seconds do
      :ok
    else
      {:error, :token_not_yet_valid}
    end
  end

  defp validate_iat(_), do: {:error, :invalid_iat}

  defp validate_exp(exp) when is_integer(exp) and exp > 0 do
    now_sec = System.system_time(:second)

    if now_sec <= exp + @clock_skew_seconds do
      {:ok, exp}
    else
      {:error, :license_expired}
    end
  end

  defp validate_exp(nil), do: {:error, :missing_expiration}
  defp validate_exp(_), do: {:error, :invalid_expiration}

  defp check_domain(_licensed_domain, nil), do: :ok
  defp check_domain(nil, _expected_domain), do: {:error, :missing_licensed_domain}

  defp check_domain(licensed_domain, expected_domain) do
    if normalize_str(licensed_domain) == normalize_str(expected_domain) do
      :ok
    else
      {:error, :domain_mismatch}
    end
  end

  defp check_email(_licensed_email, nil), do: :ok
  defp check_email(nil, _expected_email), do: {:error, :missing_licensed_email}

  defp check_email(licensed_email, expected_email) do
    if normalize_str(licensed_email) == normalize_str(expected_email) do
      :ok
    else
      {:error, :email_mismatch}
    end
  end

  defp normalize_str(%Ash.CiString{} = val), do: val |> Ash.CiString.value() |> normalize_str()
  defp normalize_str(val) when is_binary(val), do: val |> String.trim() |> String.downcase()
  defp normalize_str(val), do: val |> to_string() |> normalize_str()
end
