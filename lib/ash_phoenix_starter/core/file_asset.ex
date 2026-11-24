defmodule AshPhoenixStarter.Core.FileAsset do
  use Ash.Resource,
    domain: AshPhoenixStarter.Core,
    data_layer: AshPostgres.DataLayer

  alias AshPhoenixStarter.Uploads.{ImageUploader, StorageDispatcher, TenantConfig}

  postgres do
    table "file_assets"
    repo AshPhoenixStarter.Repo
  end

  code_interface do
    define :read, action: :read
    define :list, action: :read
    define :create, action: :create
    define :upload, action: :upload, args: [:file]
    define :update_sizes, action: :update_sizes
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :filename,
        :file_url,
        :file_size,
        :thumb_size,
        :content_type,
        :organization_id,
        :region_id,
        :type
      ]
    end

    update :update_sizes do
      accept [:file_size, :thumb_size]
    end

    create :upload do
      accept [:organization_id, :region_id, :type]

      argument :file, :map do
        allow_nil? false
        description "Map containing :file_name and either :path or :binary"
      end

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          file = Ash.Changeset.get_argument(changeset, :file)
          org_id = Ash.Changeset.get_attribute(changeset, :organization_id)
          region_id = Ash.Changeset.get_attribute(changeset, :region_id) || "global"
          type = Ash.Changeset.get_attribute(changeset, :type) || :general
          scope = %{organization_id: org_id, region_id: region_id, type: type}

          case ImageUploader.store(file, scope) do
            {:ok, stored_filename, metadata} ->
              file_url = ImageUploader.url(stored_filename, scope, :original)

              changeset
              |> Ash.Changeset.force_change_attribute(:filename, stored_filename)
              |> Ash.Changeset.force_change_attribute(:file_url, file_url)
              |> Ash.Changeset.force_change_attribute(:file_size, metadata.original_bytes)
              |> Ash.Changeset.force_change_attribute(:thumb_size, metadata.thumb_bytes)
              |> Ash.Changeset.force_change_attribute(:content_type, detect_content_type(file))

            {:error, reason} ->
              Ash.Changeset.add_error(changeset,
                field: :file,
                message: format_upload_error(reason)
              )
          end
        end)
      end

      change after_transaction(fn
               _changeset, {:ok, record}, _context ->
                 {:ok, record}

               changeset, {:error, error}, _context ->
                 rollback_uploaded_file(changeset)
                 {:error, error}
             end)
    end

    destroy :destroy do
      primary? true

      change after_transaction(fn
               _changeset, {:ok, record}, _context ->
                 delete_remote_files(record)
                 {:ok, record}

               _changeset, {:error, error}, _context ->
                 {:error, error}
             end)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :filename, :string, allow_nil?: false, public?: true
    attribute :file_url, :string, allow_nil?: false, public?: true
    attribute :file_size, :integer, default: 0, public?: true
    attribute :thumb_size, :integer, default: 0, public?: true
    attribute :content_type, :string, public?: true
    attribute :organization_id, :uuid, allow_nil?: true, public?: true
    attribute :region_id, :string, allow_nil?: false, default: "global", public?: true

    attribute :type, :atom do
      constraints one_of: [:general, :hotel_photo, :service, :feature]
      default :general
      allow_nil? false
      public? true
    end

    timestamps()
  end

  calculations do
    calculate :thumb_url, :string, fn records, _context ->
      Enum.map(records, &derive_thumb_url/1)
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp detect_content_type(%{content_type: ct}) when is_binary(ct) and ct != "", do: ct
  defp detect_content_type(%{file_name: file_name}), do: MIME.from_path(file_name)
  defp detect_content_type(_), do: "application/octet-stream"

  defp format_upload_error(:invalid_extension), do: "Unsupported file format"
  defp format_upload_error(:file_too_large), do: "File exceeds maximum allowed size"
  defp format_upload_error(:storage_quota_exceeded), do: "Monthly storage quota exceeded"
  defp format_upload_error({:imagemagick_failed, _}), do: "Failed to process image thumbnail"
  defp format_upload_error(reason), do: "Upload failed: #{inspect(reason)}"

  defp rollback_uploaded_file(changeset) do
    filename = Ash.Changeset.get_attribute(changeset, :filename)
    org_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    region_id = Ash.Changeset.get_attribute(changeset, :region_id) || "global"
    type = Ash.Changeset.get_attribute(changeset, :type) || :general

    if is_binary(filename) do
      ImageUploader.delete(filename, %{organization_id: org_id, region_id: region_id, type: type})
    end
  end

  defp delete_remote_files(%__MODULE__{
         filename: filename,
         file_url: file_url,
         file_size: file_size,
         thumb_size: thumb_size,
         organization_id: org_id,
         region_id: region_id,
         type: type
       }) do
    scope = %{organization_id: org_id, region_id: region_id || "global", type: type}
    freed_bytes = (file_size || 0) + (thumb_size || 0)

    if tus_upload?(file_url) do
      object_key = extract_object_key(file_url, org_id, region_id)
      StorageDispatcher.delete(object_key, scope)
    else
      ImageUploader.delete(filename, scope, freed_bytes)
    end
  end

  defp tus_upload?(file_url), do: String.contains?(file_url, "/tus/")

  defp derive_thumb_url(%__MODULE__{file_url: file_url}) do
    if tus_upload?(file_url) do
      file_url
    else
      dir = Path.dirname(file_url)
      ext = Path.extname(file_url)
      base = Path.basename(file_url, ext)

      if String.ends_with?(base, "_thumb"), do: file_url, else: "#{dir}/#{base}_thumb.webp"
    end
  end

  defp extract_object_key(file_url, org_id, region_id) do
    cdn = TenantConfig.cdn_url(org_id, region_id)

    cond do
      is_binary(cdn) and cdn != "" and
          String.starts_with?(file_url, String.trim_trailing(cdn, "/")) ->
        file_url
        |> String.replace_prefix(String.trim_trailing(cdn, "/"), "")
        |> String.trim_leading("/")

      true ->
        strip_bucket_from_url(file_url, org_id, region_id)
    end
  end

  defp strip_bucket_from_url(file_url, org_id, region_id) do
    bucket = TenantConfig.bucket(org_id, region_id)
    bucket_prefix = "#{bucket}/"

    case URI.parse(file_url) do
      %URI{host: host, path: path} when is_binary(path) ->
        raw_path = String.trim_leading(path, "/")
        virtual_hosted? = is_binary(host) and String.starts_with?(host, "#{bucket}.")

        if not virtual_hosted? and String.starts_with?(raw_path, bucket_prefix) do
          String.replace_prefix(raw_path, bucket_prefix, "")
        else
          raw_path
        end

      _ ->
        String.trim_leading(file_url, "/")
    end
  end
end
