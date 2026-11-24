defmodule AshPhoenixStarter.Uploads.ImageUploaderTest do
  use AshPhoenixStarter.DataCase, async: false

  alias AshPhoenixStarter.Uploads.ImageUploader

  setup do
    # Force local storage mode for tests so no external S3 calls are made
    Application.put_env(:ash_phoenix_starter, :image_mode_override, :local)

    # Generate a real 600x400 PNG fixture via ImageMagick so `store/2` exercises `convert` + WebP
    tmp_png = Path.join(System.tmp_dir!(), "fixture_#{System.unique_integer([:positive])}.png")
    {"", 0} = System.cmd("convert", ["-size", "600x400", "xc:navy", tmp_png])

    on_exit(fn ->
      File.rm(tmp_png)
      File.rm_rf("priv/static/uploads/regions/test-region")
    end)

    {:ok, fixture_path: tmp_png}
  end

  test "validates, generates a 400x400 WebP thumbnail, and scopes keys by region and org", %{
    fixture_path: fixture_path
  } do
    org_id = Ash.UUID.generate()
    region_id = "test-region"
    scope = %{type: :hotel_photo, region_id: region_id, organization_id: org_id}

    file_input = %{file_name: "lobby_view.png", path: fixture_path}

    assert {:ok, "lobby_view.png", metadata} = ImageUploader.store(file_input, scope)
    assert metadata.original_bytes > 0
    assert metadata.thumb_bytes > 0
    assert metadata.total_bytes == metadata.original_bytes + metadata.thumb_bytes

    # Verify region- and org-scoped object keys
    assert ImageUploader.object_key(:original, "lobby_view.png", scope) ==
             "uploads/regions/#{region_id}/organizations/#{org_id}/hotel_photo/lobby_view.png"

    assert ImageUploader.object_key(:thumb, "lobby_view.png", scope) ==
             "uploads/regions/#{region_id}/organizations/#{org_id}/hotel_photo/lobby_view_thumb.webp"

    # Verify bandwidth-saving thumbnail fallback when quota_exceeded?: true
    full_url = ImageUploader.url("lobby_view.png", scope, :original, quota_exceeded?: false)
    capped_url = ImageUploader.url("lobby_view.png", scope, :original, quota_exceeded?: true)

    assert String.ends_with?(full_url, "lobby_view.png")
    assert String.ends_with?(capped_url, "lobby_view_thumb.webp")

    # Clean up stored files
    assert :ok = ImageUploader.delete("lobby_view.png", scope, metadata.total_bytes)
  end
end
