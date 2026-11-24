defmodule AshPhoenixStarter.Uploads.TenantConfig do
  @moduledoc """
  Resolves per-organization and per-region storage settings and `ExAws` configuration
  from `AshPhoenixStarter.Settings.Manager` with fallback to environment variables.

  Supports `"oci"` (Oracle Cloud Object Storage S3-compatible API), `"s3"`, `"r2"`,
  `"spaces"`, `"minio"`, and `"local"`.
  """

  alias AshPhoenixStarter.Settings.Manager

  @s3_providers ~w(oci spaces s3 r2 minio)

  @spec s3_provider?(String.t() | nil) :: boolean()
  def s3_provider?(organization_id) do
    provider(organization_id) in @s3_providers
  end

  @spec provider(String.t() | nil) :: String.t()
  def provider(nil), do: default_provider()

  def provider(organization_id) do
    (Manager.get_tenant(organization_id, :storage_provider) || default_provider())
    |> String.downcase()
  end

  defp default_provider do
    System.get_env("DEFAULT_STORAGE_PROVIDER") || "local"
  end

  @spec bucket(String.t() | nil, String.t() | nil) :: String.t()
  def bucket(organization_id, region_id \\ nil)

  def bucket(nil, region_id) do
    regional_env("DEFAULT_BUCKET", region_id) ||
      System.get_env("DEFAULT_BUCKET") ||
      "app-uploads"
  end

  def bucket(organization_id, region_id) do
    get_tenant_setting(organization_id, :storage_bucket) ||
      regional_env("DEFAULT_BUCKET", region_id) ||
      System.get_env("DEFAULT_BUCKET") ||
      "app-uploads"
  end

  @spec cdn_url(String.t() | nil, String.t() | nil) :: String.t() | nil
  def cdn_url(organization_id, region_id \\ nil)

  def cdn_url(nil, region_id),
    do: regional_env("STORAGE_CDN_URL", region_id) || System.get_env("STORAGE_CDN_URL")

  def cdn_url(organization_id, region_id) do
    get_tenant_setting(organization_id, :storage_cdn_url) ||
      regional_env("STORAGE_CDN_URL", region_id) ||
      System.get_env("STORAGE_CDN_URL")
  end

  @spec virtual_host?(String.t() | nil) :: boolean()
  def virtual_host?(nil), do: false

  def virtual_host?(organization_id) do
    case Manager.get_tenant(organization_id, :storage_virtual_host) do
      val when is_boolean(val) -> val
      "true" -> true
      "false" -> false
      # OCI Object Storage S3 compatibility requires path-style URLs (virtual_host: false)
      _ -> provider(organization_id) == "r2"
    end
  end

  @spec ex_aws_config(String.t() | nil, String.t() | nil) :: keyword()
  def ex_aws_config(organization_id, region_id \\ nil) do
    provider = provider(organization_id)

    access_key =
      get_tenant_setting(organization_id, :storage_access_key) ||
        regional_env("STORAGE_ACCESS_KEY", region_id) ||
        System.get_env("STORAGE_ACCESS_KEY")

    secret_key =
      get_tenant_setting(organization_id, :storage_secret_key) ||
        regional_env("STORAGE_SECRET_KEY", region_id) ||
        System.get_env("STORAGE_SECRET_KEY")

    raw_host = resolve_raw_host(provider, organization_id, region_id)
    {scheme, clean_host, port} = parse_endpoint(provider, raw_host)

    [
      access_key_id: access_key,
      secret_access_key: secret_key,
      region: region_for_provider(provider, region_id),
      s3: [
        scheme: scheme,
        host: clean_host,
        port: port,
        virtual_host: virtual_host?(organization_id)
      ]
    ]
  end

  @spec public_url(String.t() | nil, String.t(), String.t() | nil) :: String.t()
  def public_url(organization_id, object_key, region_id \\ nil) do
    clean_key = String.trim_leading(object_key, "/")

    case cdn_url(organization_id, region_id) do
      cdn when is_binary(cdn) and cdn != "" ->
        "#{String.trim_trailing(cdn, "/")}/#{clean_key}"

      _ ->
        build_provider_url(organization_id, region_id, clean_key)
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp resolve_raw_host("oci", organization_id, region_id) do
    get_tenant_setting(organization_id, :storage_host) ||
      regional_env("OCI_STORAGE_HOST", region_id) ||
      System.get_env("OCI_STORAGE_HOST") ||
      build_oci_host_from_env(region_id)
  end

  defp resolve_raw_host("r2", organization_id, _region_id) do
    get_tenant_setting(organization_id, :storage_host) || System.get_env("R2_HOST")
  end

  defp resolve_raw_host("minio", organization_id, _region_id) do
    get_tenant_setting(organization_id, :storage_host) || "localhost:9000"
  end

  defp resolve_raw_host("spaces", organization_id, _region_id) do
    get_tenant_setting(organization_id, :storage_host) || "digitaloceanspaces.com"
  end

  defp resolve_raw_host(_provider, organization_id, _region_id) do
    get_tenant_setting(organization_id, :storage_host) || "amazonaws.com"
  end

  # Builds "<namespace>.compat.objectstorage.<oci_region>.oraclecloud.com" automatically
  defp build_oci_host_from_env(region_id) do
    namespace = System.get_env("OCI_OBJECT_STORAGE_NAMESPACE")
    oci_region = region_for_provider("oci", region_id)

    if namespace do
      "#{namespace}.compat.objectstorage.#{oci_region}.oraclecloud.com"
    else
      nil
    end
  end

  defp build_provider_url(organization_id, region_id, clean_key) do
    if s3_provider?(organization_id) do
      aws_cfg = ex_aws_config(organization_id, region_id)
      s3_cfg = Keyword.get(aws_cfg, :s3, [])
      scheme = Keyword.get(s3_cfg, :scheme, "https://")
      host = Keyword.get(s3_cfg, :host, "amazonaws.com")
      bucket = bucket(organization_id, region_id)

      if virtual_host?(organization_id) do
        "#{scheme}#{bucket}.#{host}/#{clean_key}"
      else
        "#{scheme}#{host}/#{bucket}/#{clean_key}"
      end
    else
      "/#{clean_key}"
    end
  end

  defp parse_endpoint(provider, raw_host) do
    host_str = raw_host || ""

    cond do
      String.starts_with?(host_str, "http://") ->
        stripped = String.replace_prefix(host_str, "http://", "")
        {"http://", stripped, extract_port(stripped, 80)}

      String.starts_with?(host_str, "https://") ->
        stripped = String.replace_prefix(host_str, "https://", "")
        {"https://", stripped, extract_port(stripped, 443)}

      provider == "minio" ->
        {"http://", host_str, extract_port(host_str, 9000)}

      true ->
        {"https://", host_str, extract_port(host_str, 443)}
    end
  end

  defp extract_port(host, default_port) do
    case String.split(host, ":") do
      [_hostname, port_str] -> String.to_integer(port_str)
      _ -> default_port
    end
  end

  defp get_tenant_setting(nil, _key), do: nil

  defp get_tenant_setting(organization_id, key) do
    case Manager.get_tenant(organization_id, key) do
      val when is_binary(val) ->
        case String.trim(val) do
          "" -> nil
          trimmed -> trimmed
        end

      val ->
        val
    end
  end

  # Checks for region-specific env vars like DEFAULT_BUCKET_US_ASHBURN_1
  defp regional_env(_base_key, nil), do: nil

  defp regional_env(base_key, region_id) do
    normalized_region =
      region_id
      |> to_string()
      |> String.upcase()
      |> String.replace(~r/[^A-Z0-9]/, "_")

    System.get_env("#{base_key}_#{normalized_region}")
  end

  defp region_for_provider("r2", _region_id), do: "auto"

  defp region_for_provider("oci", region_id) do
    regional_env("OCI_REGION", region_id) ||
      System.get_env("OCI_REGION") ||
      region_id ||
      "us-ashburn-1"
  end

  defp region_for_provider("s3", region_id) do
    regional_env("AWS_REGION", region_id) ||
      System.get_env("AWS_REGION") ||
      "us-east-1"
  end

  defp region_for_provider(_, _region_id), do: "us-east-1"
end
