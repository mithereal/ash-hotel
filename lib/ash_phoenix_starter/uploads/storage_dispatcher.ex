defmodule AshPhoenixStarter.Uploads.StorageDispatcher do
  @moduledoc """
  Unified storage router for standard object uploads (`ImageUploader`, `FileAsset`),
  direct browser presigned uploads, and resumable chunked uploads (`Tussle`).
  """

  alias AshPhoenixStarter.Settings.Manager
  alias AshPhoenixStarter.Uploads.TenantConfig

  @local_root "priv/static"

  # ============================================================================
  # 1. STANDARD & PRESIGNED OBJECT STORAGE
  # ============================================================================

  @spec presigned_put_url(String.t(), map(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def presigned_put_url(object_key, scope, opts \\ []) do
    {org_id, region_id} = extract_scope(scope)
    clean_key = String.trim_leading(object_key, "/")

    case resolve_backend(org_id) do
      :s3 ->
        bucket = resolve_bucket(org_id, region_id)
        aws_cfg = resolve_aws_config(org_id, region_id)
        expires_in = Keyword.get(opts, :expires_in, 900)
        content_type = Keyword.get_lazy(opts, :content_type, fn -> MIME.from_path(clean_key) end)

        ExAws.S3.presigned_url(
          aws_cfg,
          :put,
          bucket,
          clean_key,
          expires_in: expires_in,
          query_params: [{"Content-Type", content_type}]
        )

      :local ->
        {:error, :presigned_urls_require_s3}
    end
  end

  @spec put(String.t(), {:path, String.t()} | binary(), map(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def put(object_key, binary_or_path, scope, opts \\ []) do
    {org_id, region_id} = extract_scope(scope)
    clean_key = String.trim_leading(object_key, "/")

    case resolve_backend(org_id) do
      :s3 -> put_s3(org_id, region_id, clean_key, binary_or_path, opts)
      :local -> put_local(clean_key, binary_or_path)
    end
  end

  @spec delete(String.t(), map()) :: :ok | {:error, term()}
  def delete(object_key, scope) when is_binary(object_key) do
    {org_id, region_id} = extract_scope(scope)
    clean_key = String.trim_leading(object_key, "/")

    case resolve_backend(org_id) do
      :s3 ->
        bucket = resolve_bucket(org_id, region_id)
        aws_cfg = resolve_aws_config(org_id, region_id)

        case ExAws.S3.delete_object(bucket, clean_key) |> ExAws.request(aws_cfg) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      :local ->
        case File.rm(Path.join(@local_root, clean_key)) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec url(String.t(), map()) :: String.t()
  def url(object_key, scope) do
    {org_id, region_id} = extract_scope(scope)
    clean_key = String.trim_leading(object_key, "/")

    case resolve_backend(org_id) do
      :s3 -> resolve_public_url(org_id, region_id, clean_key)
      :local -> "/#{clean_key}"
    end
  end

  # ============================================================================
  # 2. TUSSLE STORAGE CALLBACKS (WITH QUOTA & BANDWIDTH METERING)
  # ============================================================================

  def create(file, config) when is_map(config) do
    {org_id, region_id} = resolve_tus_scope(file, config)

    with :ok <- check_tus_quota(org_id, region_id, Map.get(file, :size, 0)) do
      backend = resolve_tus_backend(org_id)
      backend.create(file, prepare_tus_config(backend, org_id, region_id, config))
    end
  end

  def append(file, config, body) when is_map(config) do
    {org_id, region_id} = resolve_tus_scope(file, config)
    chunk_bytes = byte_size(body)

    with :ok <- check_tus_quota(org_id, region_id, chunk_bytes) do
      backend = resolve_tus_backend(org_id)

      case backend.append(file, prepare_tus_config(backend, org_id, region_id, config), body) do
        {:ok, _} = ok ->
          emit_tus_usage(:tus_chunk_ingress, chunk_bytes, org_id, region_id)
          ok

        other ->
          other
      end
    end
  end

  def complete_upload(file, config) when is_map(config) do
    {org_id, region_id} = resolve_tus_scope(file, config)
    backend = resolve_tus_backend(org_id)
    backend.complete_upload(file, prepare_tus_config(backend, org_id, region_id, config))
  end

  def delete(file, config) when is_map(config) do
    {org_id, region_id} = resolve_tus_scope(file, config)
    backend = resolve_tus_backend(org_id)
    backend.delete(file, prepare_tus_config(backend, org_id, region_id, config))
  end

  # ============================================================================
  # 3. PRIVATE HELPERS
  # ============================================================================

  defp put_s3(org_id, region_id, clean_key, {:path, file_path}, opts) do
    bucket = resolve_bucket(org_id, region_id)
    aws_cfg = resolve_aws_config(org_id, region_id)
    s3_opts = build_s3_put_opts(clean_key, opts)

    file_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(bucket, clean_key, s3_opts)
    |> ExAws.request(aws_cfg)
    |> case do
      {:ok, _} -> {:ok, clean_key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_s3(org_id, region_id, clean_key, binary, opts) when is_binary(binary) do
    bucket = resolve_bucket(org_id, region_id)
    aws_cfg = resolve_aws_config(org_id, region_id)
    s3_opts = build_s3_put_opts(clean_key, opts)

    ExAws.S3.put_object(bucket, clean_key, binary, s3_opts)
    |> ExAws.request(aws_cfg)
    |> case do
      {:ok, _} -> {:ok, clean_key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_local(clean_key, {:path, source_path}) do
    dest_path = Path.join(@local_root, clean_key)
    File.mkdir_p!(Path.dirname(dest_path))

    case File.cp(source_path, dest_path) do
      :ok -> {:ok, clean_key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_local(clean_key, binary) when is_binary(binary) do
    dest_path = Path.join(@local_root, clean_key)
    File.mkdir_p!(Path.dirname(dest_path))

    case File.write(dest_path, binary) do
      :ok -> {:ok, clean_key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_s3_put_opts(key, opts) do
    content_type = Keyword.get_lazy(opts, :content_type, fn -> MIME.from_path(key) end)
    acl = Keyword.get(opts, :acl, :public_read)
    [content_type: content_type, acl: acl]
  end

  defp resolve_bucket(org_id, region_id) do
    if function_exported?(TenantConfig, :bucket, 2),
      do: TenantConfig.bucket(org_id, region_id),
      else: TenantConfig.bucket(org_id)
  end

  defp resolve_aws_config(org_id, region_id) do
    if function_exported?(TenantConfig, :ex_aws_config, 2),
      do: TenantConfig.ex_aws_config(org_id, region_id),
      else: TenantConfig.ex_aws_config(org_id)
  end

  defp resolve_public_url(org_id, region_id, clean_key) do
    if function_exported?(TenantConfig, :public_url, 3),
      do: TenantConfig.public_url(org_id, region_id, clean_key),
      else: TenantConfig.public_url(org_id, clean_key)
  end

  defp resolve_backend(org_id) do
    if Manager.get(:image_mode) == :local do
      :local
    else
      if TenantConfig.s3_provider?(org_id), do: :s3, else: :local
    end
  end

  defp resolve_tus_backend(org_id) do
    if TenantConfig.s3_provider?(org_id), do: Tussle.Storage.S3, else: Tussle.Storage.Local
  end

  defp prepare_tus_config(Tussle.Storage.S3, org_id, region_id, config) do
    region_part = if region_id, do: "regions/#{region_id}", else: "global"

    prefix =
      if org_id,
        do: "uploads/#{region_part}/organizations/#{org_id}/tus",
        else: "uploads/#{region_part}/tus"

    config
    |> Map.put(:organization_id, org_id)
    |> Map.put(:region_id, region_id)
    |> Map.put_new(:s3_prefix, prefix)
  end

  defp prepare_tus_config(Tussle.Storage.Local, org_id, region_id, config) do
    region_part = if region_id, do: "regions/#{region_id}", else: "global"

    dir =
      if org_id,
        do: "priv/static/uploads/#{region_part}/organizations/#{org_id}/tus",
        else: "priv/static/uploads/#{region_part}/tus"

    Map.put(config, :base_path, dir)
  end

  defp resolve_tus_scope(file, config) do
    org_id = Map.get(config, :organization_id) || get_in(file, [:metadata, "organization_id"])
    region_id = Map.get(config, :region_id) || get_in(file, [:metadata, "region_id"])
    {org_id, region_id}
  end

  defp extract_scope(scope) when is_map(scope),
    do: {Map.get(scope, :organization_id), Map.get(scope, :region_id)}

  defp extract_scope(_), do: {nil, nil}

  defp check_tus_quota(nil, _region_id, _bytes), do: :ok

  defp check_tus_quota(org_id, region_id, bytes) do
    region = region_id || "global"

    if function_exported?(AshPhoenixStarter.Billing.UsageTracker, :allow_storage?, 3) and
         not AshPhoenixStarter.Billing.UsageTracker.allow_storage?(region, org_id, bytes) do
      {:error, :storage_quota_exceeded}
    else
      :ok
    end
  end

  defp emit_tus_usage(event, bytes, org_id, region_id) do
    :telemetry.execute(
      [:ash_phoenix_starter, :storage, event],
      %{bytes: bytes},
      %{region_id: region_id || "global", organization_id: org_id}
    )
  end
end
