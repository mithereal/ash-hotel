
Phase 1: Provision OCI Infrastructure (us-phoenix-1 First)

1. Create your VCN (10.0.0.0/16) in us-phoenix-1:
	• Public Subnet (10.0.1.0/24): Allow ingress TCP 22, 80, and 443 from 0.0.0.0/0.
	• Private Subnet (10.0.2.0/24): Allow ingress TCP 5432 from 10.0.1.0/24 and 100.64.0.0/10 (Tailscale).
2. Launch OCI Managed PostgreSQL in the Private Subnet (10.0.2.0/24). Copy its private IP (e.g., 10.0.2.15) and database credentials.
3. Launch Your Primary App VM (us-phoenix-1):
	• Shape: VM.Standard.A1.Flex (4 OCPUs, 24 GB RAM — Always Free), Ubuntu 24.04 ARM64, placed in the Public Subnet.
4. Launch Your Secondary App VM (us-ashburn-1):
	• Shape: VM.Standard.A1.Flex (2 OCPUs, 12 GB RAM), Ubuntu 24.04 ARM64.
5. Create OCI Object Storage Bucket (hotel-media-prod) in us-phoenix-1:
	• Set Visibility to Public (or configure Cloudflare Transform Rule), add CORS rules allowing PUT, GET, HEAD, OPTIONS from https://yourdomain.com, and generate a Customer Secret Key under User Settings → Customer Secret Keys.

Phase 2: Connect the VMs with Tailscale & Docker

SSH into both VMs and install Docker + Tailscale:
bash
# Install Docker & Docker Compose
curl -fsSL https://docker.com | sh
sudo usermod -aG docker $USER

# Install Tailscale
curl -fsSL https://tailscale.com | sh

1. On the us-phoenix-1 VM (Subnet Router to Managed Postgres):bash
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sudo tailscale up --advertise-routes=10.0.2.0/24 --accept-dns=false

(Approve the 10.0.2.0/24 route in your Tailscale Admin Console, and note both VMs' 100.64.x.x Tailscale IPs.)
2. On the us-ashburn-1 VM:bash
sudo tailscale up --accept-routes --accept-dns=false

3. Open Erlang Cluster Ports on tailscale0 (Both VMs):bash
sudo iptables -I INPUT 1 -i tailscale0 -p tcp --dport 4369 -j ACCEPT
sudo iptables -I INPUT 1 -i tailscale0 -p tcp --dport 9000:9100 -j ACCEPT
sudo netfilter-persistent save


Phase 3: Configure Environment, Caddy & Compose on Both VMs

1. Create /etc/ash_phoenix_starter.env (sudo chmod 600):
	• Set RELEASE_NODE=app_us_phoenix_1@100.64.0.1 on Phoenix and RELEASE_NODE=app_us_ashburn_1@100.64.0.2 on Ashburn.
	• Set CLUSTER_NODES=app_us_phoenix_1@100.64.0.1,app_us_ashburn_1@100.64.0.2 and identical RELEASE_COOKIE on both.
	• Set DATABASE_URL=ecto://user:pass@10.0.2.15:5432/ash_phoenix_starter_prod (uses the Tailscale subnet route from Ashburn automatically).
	• Add your OCI_*, STORAGE_*, STRIPE_SECRET_KEY, and INTERNAL_WORKER_SECRET keys.
2. Install & start Caddy on both VMs (/etc/caddy/Caddyfile proxying :80/:443 → 127.0.0.1:4000).
3. Place /opt/ash_phoenix_starter/docker-compose.yml (with network_mode: host) on both VMs and log in to OCIR (docker login <region>.ocir.io).

Phase 4: Push Code & Trigger CircleCI Deploy

1. Generate Ash migrations locally & commit everything:bash
mix ash.codegen add_tenant_usages_and_regions
mix test
git add . && git commit -m "Multi-region OCI cluster and bandwidth metering"
git push origin main

2. Watch CircleCI:
	• test runs mix test against Postgres 16 + ImageMagick/WebP.
	• build_and_push_ocir builds the ARM64 runner image and pushes :latest to OCIR.
	• Rolling SSH step pulls and restarts us-phoenix-1 first (start.sh runs mix ecto.migrate automatically on boot), waits 10 seconds, and restarts us-ashburn-1.

Phase 5: Verify Cluster & Cloudflare Routing

1. Verify Erlang + Horde clustering from the us-phoenix-1 VM:bash
docker exec -it ash_phoenix_starter /app/bin/AshPhoenixStarter remote

Run inside IEx:elixir
Node.list()
# => [:"app_us_ashburn_1@100.64.0.2"]

Horde.Cluster.members(AshPhoenixStarter.HordeRegistry)
# => Both nodes listed

2. Switch Cloudflare DNS / Load Balancer to point yourdomain.com (WNAM → Phoenix, ENAM/WEU → Ashburn) and ://yourdomain.com (CNAME → OCI Object Storage).
3. Log into /admin/regions on your live site to verify both OCI nodes appear online and test uploading a hotel photo at /hotel/media.