defmodule AshPhoenixStarter.Provisioner do
  @base_url "https://api.digitalocean.com/v2"

  @doc """
  Spins up a new Droplet for a customer using a pre-configured snapshot ID.
  """
  def create_customer_droplet(
        customer_email,
        snapshot_id \\ nil,
        ssh_keys \\ [],
        region \\ nil,
        size \\ nil,
        backups \\ false,
        monitoring \\ true
      ) do
    api_token = System.fetch_env!("DO_API_TOKEN")

    backups = if backups, do: System.fetch_env!("DO_BACKUPS") == "true", else: backups
    monitoring = if monitoring, do: System.fetch_env!("DO_MONITORING") == "true", else: monitoring
    snapshot_id = snapshot_id || System.fetch_env!("DO_SNAPSHOT_ID")
    region = region || System.fetch_env!("DO_REGION") || "nyc1"
    size = size || System.fetch_env!("DO_SIZE") || "s-1vcpu-1gb"

    ssh_keys =
      if Enum.empty?(ssh_keys) do
        System.fetch_env!("DO_SSH_KEYS") |> String.split(",") |> Enum.map(&String.trim/1)
      else
        ssh_keys
      end

    payload = %{
      name: "app-#{generate_slug(customer_email)}",
      region: region,
      size: size,
      image: snapshot_id,
      ssh_keys: ssh_keys,
      backups: backups,
      monitoring: monitoring,
      tags: ["customer-instance", "managed-app"]
    }

    case Req.post("#{@base_url}/droplets",
           json: payload,
           headers: [
             {"Authorization", "Bearer #{api_token}"},
             {"Content-Type", "application/json"}
           ]
         ) do
      {:ok, %{status: 202, body: body}} ->
        droplet_id = get_in(body, ["droplet", "id"])
        {:ok, droplet_id}

      {:ok, %{status: status, body: body}} ->
        {:error, "DigitalOcean API error (#{status}): #{inspect(body)}"}

      {:error, exception} ->
        {:error, exception}
    end
  end

  # Helper to generate a clean subdomain/hostname slug from email
  defp generate_slug(email) do
    email
    |> String.split("@")
    |> hd()
    |> String.downcase()
    |> Regex.replace(~r/[^a-z0-9]/, "-")
  end
end
