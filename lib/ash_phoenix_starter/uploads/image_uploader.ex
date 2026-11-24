defmodule AshPhoenixStarter.Uploads.ImageUploader do
  @moduledoc """
  Handles image validation, WebP thumbnail generation via ImageMagick,
  regional multi-version storage via `StorageDispatcher`, and usage metering.
  """

  alias AshPhoenixStarter.Settings.Manager
  alias AshPhoenixStarter.Uploads.StorageDispatcher

  @extensions ~w(jpg jpeg png webp)
  @default_max_size 500 * 1024 * 1024

  @type file_input :: %{
          required(:file_name) => String.t(),
          optional(:path) => String.t(),
          optional(:binary) => binary()
        }

  @type scope :: %{
          required(:type) => atom(),
          optional(:region_id) => String.t() | nil,
          optional(:organization_id) => String.t() | nil
        }

  @type upload_metadata :: %{
          file_name: String.t(),
          original_bytes: non_neg_integer(),
          thumb_bytes: non_neg_integer(),
          total_bytes: non_neg_integer()
        }

  @doc """
  Validates quota and file rules, generates `:original` and WebP `:thumb` versions,
  uploads both, and emits storage telemetry for tenant billing.
  Returns `{:ok, base_filename, metadata}`.
  """
  @spec store(file_input(), scope()) :: {:ok, String.t(), upload_metadata()} | {:error, term()}
  def store(file, scope) do
    with {:ok, original_bytes} <- validate(file, scope),
         {:ok, source_path, cleanup?} <- ensure_temp_file(file),
         {:ok, thumb_path, thumb_bytes} <- generate_thumbnail(source_path) do
      try do
        original_key = object_key(:original, file.file_name, scope)
        thumb_key = object_key(:thumb, file.file_name, scope)

        with {:ok, _} <- StorageDispatcher.put(original_key, {:path, source_path}, scope),
             {:ok, _} <- StorageDispatcher.put(thumb_key, {:path, thumb_path}, scope) do
          base_name = Path.basename(file.file_name)

          metadata = %{
            file_name: base_name,
            original_bytes: original_bytes,
            thumb_bytes: thumb_bytes,
            total_bytes: original_bytes + thumb_bytes
          }

          emit_usage(:upload, metadata.total_bytes, scope)

          {:ok, base_name, metadata}
        end
      after
        File.rm(thumb_path)
        if cleanup?, do: File.rm(source_path)
      end
    end
  end

  @doc """
  Deletes both `:original` and `:thumb` versions from storage.
  Pass `freed_bytes` if tracked on your Ash resource to decrement the hotel's storage quota.
  """
  @spec delete(String.t() | nil, scope(), non_neg_integer()) :: :ok
  def delete(file_name, scope, freed_bytes \\ 0)
  def delete(nil, _scope, _freed_bytes), do: :ok

  def delete(file_name, scope, freed_bytes) when is_binary(file_name) do
    StorageDispatcher.delete(object_key(:original, file_name, scope), scope)
    StorageDispatcher.delete(object_key(:thumb, file_name, scope), scope)

    if freed_bytes > 0 do
      emit_usage(:delete, -freed_bytes, scope)
    end

    :ok
  end

  @doc """
  Resolves the public/CDN URL for `:original` or `:thumb`.
  Automatically downgrades `:original` to `:thumb` if `quota_exceeded?: true` is passed in opts
  so guest booking pages stay online without blowing through your bandwidth limits.
  """
  @spec url(String.t() | nil, scope(), :original | :thumb, keyword()) :: String.t() | nil
  def url(file_name, scope, version \\ :original, opts \\ [])
  def url(nil, _scope, _version, _opts), do: nil

  def url(file_name, scope, version, opts) when version in [:original, :thumb] do
    effective_version =
      if Keyword.get(opts, :quota_exceeded?, false) and version == :original do
        :thumb
      else
        version
      end

    key = object_key(effective_version, file_name, scope)

    if byte_size = Keyword.get(opts, :known_bytes) do
      emit_usage(:egress_estimate, byte_size, scope)
    end

    StorageDispatcher.url(key, scope)
  end

  @doc """
  Builds a region- and tenant-scoped storage key so CDN logs and regional buckets
  can attribute bandwidth directly to a region and hotel (`organization_id`).
  """
  @spec object_key(:original | :thumb, String.t(), scope()) :: String.t()
  def object_key(version, file_name, scope) do
    dir = storage_dir(scope) |> String.trim("/")
    stem = Path.basename(file_name, Path.extname(file_name))

    filename =
      case version do
        :original -> "#{stem}#{Path.extname(file_name)}"
        :thumb -> "#{stem}_thumb.webp"
      end

    "#{dir}/#{filename}"
  end

  def storage_dir(scope) do
    region_prefix =
      case Map.get(scope, :region_id) do
        nil -> "global"
        region_id -> "regions/#{region_id}"
      end

    case scope.type do
      :service -> "uploads/#{region_prefix}/service"
      :feature -> "uploads/#{region_prefix}/feature"
      _ -> "uploads/#{region_prefix}/organizations/#{scope.organization_id}/#{scope.type}"
    end
  end

  # ============================================================================
  # VALIDATION, QUOTA & IMAGE PROCESSING
  # ============================================================================

  def validate(file, scope \\ %{}) do
    with :ok <- check_extension(file),
         {:ok, size} <- check_file_size(file),
         :ok <- check_tenant_quota(size, scope) do
      {:ok, size}
    end
  end

  defp check_extension(%{file_name: file_name}) do
    valid? =
      file_name
      |> Path.extname()
      |> String.downcase()
      |> String.trim_leading(".")
      |> then(&(&1 in @extensions))

    if valid?, do: :ok, else: {:error, :invalid_extension}
  end

  defp check_file_size(file) do
    max_size = Manager.get(:max_upload_size) || @default_max_size

    case get_file_size(file) do
      {:ok, size} when size <= max_size -> {:ok, size}
      {:ok, _size} -> {:error, :file_too_large}
      :error -> {:error, :unreadable_file}
    end
  end

  # Hook into your Horde UsageTracker GenServer here to block uploads if the hotel is over quota
  defp check_tenant_quota(_incoming_bytes, %{organization_id: nil}), do: :ok

  defp check_tenant_quota(incoming_bytes, %{organization_id: org_id} = scope) do
    region_id = Map.get(scope, :region_id, "global")

    if function_exported?(AshPhoenixStarter.Billing.UsageTracker, :allow_storage?, 3) do
      if AshPhoenixStarter.Billing.UsageTracker.allow_storage?(region_id, org_id, incoming_bytes) do
        :ok
      else
        {:error, :storage_quota_exceeded}
      end
    else
      :ok
    end
  end

  defp check_tenant_quota(_incoming_bytes, _scope), do: :ok

  defp get_file_size(%{size: size}) when is_integer(size) and size > 0, do: {:ok, size}

  defp get_file_size(%{binary: binary}) when is_binary(binary), do: {:ok, byte_size(binary)}

  defp get_file_size(%{path: path}) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> {:ok, size}
      {:error, _} -> :error
    end
  end

  defp get_file_size(_), do: :error

  defp ensure_temp_file(%{path: path}) when is_binary(path), do: {:ok, path, false}

  defp ensure_temp_file(%{binary: binary, file_name: file_name}) when is_binary(binary) do
    ext = Path.extname(file_name)
    tmp_path = Path.join(System.tmp_dir!(), "upload_#{System.unique_integer([:positive])}#{ext}")

    case File.write(tmp_path, binary) do
      :ok -> {:ok, tmp_path, true}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_thumbnail(source_path) do
    thumb_path =
      Path.join(System.tmp_dir!(), "thumb_#{System.unique_integer([:positive])}.webp")

    args = [
      source_path,
      "-auto-orient",
      "-strip",
      "-thumbnail",
      "400x400^",
      "-gravity",
      "center",
      "-extent",
      "400x400",
      "-quality",
      "82",
      thumb_path
    ]

    case System.cmd("convert", args, stderr_to_stdout: true) do
      {_output, 0} ->
        case File.stat(thumb_path) do
          {:ok, %File.Stat{size: size}} -> {:ok, thumb_path, size}
          {:error, reason} -> {:error, reason}
        end

      {error, _code} ->
        {:error, {:imagemagick_failed, error}}
    end
  end

  defp emit_usage(event, bytes, scope) do
    :telemetry.execute(
      [:ash_phoenix_starter, :storage, event],
      %{bytes: bytes},
      %{
        region_id: Map.get(scope, :region_id, "global"),
        organization_id: Map.get(scope, :organization_id),
        type: scope.type
      }
    )
  end
end
