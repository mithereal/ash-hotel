defmodule AshPhoenixStarter.Uploads.Workers.GenerateThumbnailWorker do
  @moduledoc """
  Downloads a newly uploaded original image from OCI Object Storage / S3,
  generates a 400x400 WebP thumbnail, uploads it back, and records total
  storage bytes in `UsageTracker`.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias AshPhoenixStarter.Uploads.{ImageUploader, StorageDispatcher, TenantConfig}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "file_name" => file_name,
          "organization_id" => org_id,
          "region_id" => region_id,
          "type" => type_str
        }
      }) do
    scope = %{
      type: String.to_existing_atom(type_str),
      organization_id: org_id,
      region_id: region_id
    }

    original_key = ImageUploader.object_key(:original, file_name, scope)
    thumb_key = ImageUploader.object_key(:thumb, file_name, scope)

    tmp_dir = System.tmp_dir!()
    uid = System.unique_integer([:positive])
    tmp_orig = Path.join(tmp_dir, "orig_#{uid}#{Path.extname(file_name)}")
    tmp_thumb = Path.join(tmp_dir, "thumb_#{uid}.webp")

    try do
      with {:ok, original_bytes} <- download_original(org_id, region_id, original_key, tmp_orig),
           {:ok, thumb_bytes} <- create_webp_thumb(tmp_orig, tmp_thumb),
           {:ok, _} <- StorageDispatcher.put(thumb_key, {:path, tmp_thumb}, scope) do
        # Record exact storage usage for both files in Horde UsageTracker
        :telemetry.execute(
          [:ash_phoenix_starter, :storage, :upload],
          %{bytes: original_bytes + thumb_bytes},
          %{
            region_id: region_id || "global",
            organization_id: org_id,
            type: scope.type
          }
        )

        if asset_id = args["file_asset_id"] do
          with {:ok, asset} <- Ash.get(FileAsset, asset_id, authorize?: false) do
            FileAsset.update_sizes(
              asset,
              %{file_size: original_bytes, thumb_size: thumb_bytes},
              authorize?: false
            )
          end
        end

        :ok
      end
    after
      File.rm(tmp_orig)
      File.rm(tmp_thumb)
    end
  end

  defp download_original(org_id, region_id, key, dest_path) do
    bucket = TenantConfig.bucket(org_id, region_id)
    aws_cfg = TenantConfig.ex_aws_config(org_id, region_id)

    case ExAws.S3.download_file(bucket, key, dest_path) |> ExAws.request(aws_cfg) do
      {:ok, :done} ->
        case File.stat(dest_path) do
          {:ok, %File.Stat{size: size}} -> {:ok, size}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_webp_thumb(source_path, thumb_path) do
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
      {_out, 0} ->
        case File.stat(thumb_path) do
          {:ok, %File.Stat{size: size}} -> {:ok, size}
          {:error, reason} -> {:error, reason}
        end

      {err, _code} ->
        {:error, {:imagemagick_failed, err}}
    end
  end
end
