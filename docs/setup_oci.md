Step 1: Open Ports in OCI VCN Security List (or NSG)

In your Oracle Cloud Console (Networking → Virtual Cloud Networks → Your VCN → Security Lists → Default Security List), add these Ingress Rules:
• Public Web Traffic (from 0.0.0.0/0):
	• TCP Port 80 (HTTP) and 443 (HTTPS)
• Erlang Clustering (from your VCN Subnet CIDR, e.g., 10.0.0.0/16, or your Tailscale CIDR 100.64.0.0/10):
	• TCP Port 4369 (EPMD — Erlang Port Mapper Daemon)
	• TCP Port Range 9000-9100 (Erlang distributed node-to-node communication)

Step 2: Pin Erlang Distribution Ports in rel/vm.args.eex

By default, Erlang picks a random high port for clustering, which firewalls block. Run mix release.init (if you don't have a rel/ folder yet) and add these lines to rel/vm.args.eex:
text
## Pin Erlang distribution ports so OCI firewall rules work reliably
-kernel inet_dist_listen_min 9000
-kernel inet_dist_listen_max 9100

## Tune net_ticktime for multi-region OCI VMs (prevents false netsplits on brief latency spikes)
-kernel net_ticktime 60


Step 3: Open Ports on the OCI VM OS Firewall

Oracle Cloud's default Ubuntu and Oracle Linux images block non-SSH ports in iptables even when your VCN Security List allows them. SSH into each OCI VM and run:
On Ubuntu (OCI Compute):
bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp -s 10.0.0.0/16 --dport 4369 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp -s 10.0.0.0/16 --dport 9000:9100 -j ACCEPT
sudo netfilter-persistent save

(If you connect multi-region OCI VMs over Tailscale instead of a peered VCN, replace 10.0.0.0/16 above with 100.64.0.0/10.)

/etc/systemd/system/ash_phoenix_starter.service (adjust User and ExecStart path to match where you unpack your release)


Step 3: Enable, Start & Verify Cluster Connection

Run these commands on your OCI VM:
bash
sudo systemctl daemon-reload
sudo systemctl enable ash_phoenix_starter
sudo systemctl start ash_phoenix_starter

Once two regional VMs are running, verify they have formed a cluster and joined Horde by attaching to a remote IEx shell on one of the VMs:
bash
/opt/ash_phoenix_starter/bin/ash_phoenix_starter remote

Inside IEx, run:
elixir
Node.list()
# => [:"app_eu_frankfurt_1@10.0.2.10"]

Horde.Cluster.members(AshPhoenixStarter.HordeRegistry)
# => [{AshPhoenixStarter.HordeRegistry, :"app_us_ashburn_1@10.0.1.10"}, {AshPhoenixStarter.HordeRegistry, :"app_eu_frankfurt_1@10.0.2.10"}]

(Tip: Place Caddy or Nginx in front of port 4000 on each VM to handle automatic Let's Encrypt SSL certificates on ports 80/443 and reverse-proxy WebSockets cleanly to Bandit.)


Part 1: Install Caddy & Configure /etc/caddy/Caddyfile


1. Install Caddy on Ubuntu (OCI Compute)

bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://cloudsmith.io' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://cloudsmith.io' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy


2. Configure /etc/caddy/Caddyfile


3. Reload Caddy & uncomment config/runtime.exs

Run sudo systemctl reload caddy. 

Because you are running Horde across your Oracle Cloud VMs, restarting nodes one at a time gives you true zero-downtime deploys: when Node 1 stops, UsageTracker.terminate/2 flushes pending usage bytes to Postgres, Horde migrates active processes to Node 2, and once Node 1 boots back up with the new release, it rejoins the cluster automatically.

In your CircleCI project settings (Project Settings → Environment Variables), add:
• OCIR_REGION_KEY — Your OCI region key (e.g., iad for Ashburn, fra for Frankfurt, phx for Phoenix).
• OCIR_NAMESPACE — Your OCI Object Storage / Tenancy namespace.
• OCIR_USERNAME — <OCIR_NAMESPACE>/<your_oci_username> (or <OCIR_NAMESPACE>/oracleidentitycloudservice/<email> if federated).
• OCIR_AUTH_TOKEN — Your OCI User Auth Token (generated under OCI Console → User Settings → Auth Tokens).
• OCIR_REPO — Your container repository name (e.g., ash-phoenix-starter).

 Add Your SSH Key & Node List to CircleCI

1. Add SSH Private Key: In CircleCI under Project Settings → SSH Keys → Additional SSH Keys, add your private SSH key (Hostname: leave blank so it works for all your OCI VMs). Copy its Fingerprint.
2. Add Environment Variable: Under Project Settings → Environment Variables, add:
	• OCI_NODES — Space-separated list of your OCI VMs (e.g., ubuntu@10.0.1.10 ubuntu@10.0.2.10 or their public/Tailscale IPs).


Important Architecture Note

• Match resource_class to your OCI VM CPU: Keep resource_class: arm.medium if your OCI VMs are Ampere ARM (VM.Standard.A1.Flex), or swap resource_class: arm.medium to resource_class: medium if your OCI VMs are Intel/AMD (x86_64).
• Pulling on your OCI VMs: Once pushed, each OCI regional VM can pull and restart with docker pull <region>.ocir.io/<namespace>/ash-phoenix-starter:latest using --network host (so Erlang distribution ports 4369 and 9000–9100 work across VMs without Docker NAT issues).

Create /opt/ash_phoenix_starter/docker-compose.yml on Each OCI VM


Log In & Start on Your OCI VM

#### we have a workflow task that does this this is ere for legacy reasons
Run these commands once on each OCI VM inside /opt/ash_phoenix_starter:
bash
# Log in to OCIR so the VM can pull your private image
echo "<OCIR_AUTH_TOKEN>" | docker login <region_key>.ocir.io \
  --username "<namespace>/<username>" \
  --password-stdin

# Pull and start in the background
docker compose pull
docker compose up -d


 Rolling Update Command for Future Deploys

Whenever CircleCI pushes a new :latest image to OCIR, update your regional OCI VMs one by one with:
bash
docker compose pull && docker compose up -d

## final steps
Set CORS & Public Read Rules on Your OCI Bucket

Because hotel managers upload directly from their browser (Uploaders.S3 → presigned_put_url) and guests view photos directly from OCI/Cloudflare:
• OCI Object Storage Bucket CORS: Allow PUT, GET, HEAD, and OPTIONS from https://yourdomain.com (and http://localhost:4000 for dev) with allowed header Content-Type.
• Bucket Visibility / Cloudflare: Put Cloudflare in front of your OCI bucket (STORAGE_CDN_URL=https://yourdomain.com) so OCI's Bandwidth Alliance waives egress fees from Object Storage to Cloudflare.


Optional: How Bling Receives Your Metered Overage Events

In your Stripe Dashboard (which Bling syncs with):
1. Create a Billing Meter with Event Name set to hotel_platform_overage_gb and aggregation set to Sum on payload value.
2. Attach a Metered Price (e.g., $0.10–$0.25 per overage GB) using that meter to your $1–$10/month hotel subscription products in Stripe—Bling will automatically include any reported overage GBs on the hotel's next monthly Stripe invoice without extra webhook code.

Add INTERNAL_WORKER_SECRET=<long_random_secret> to both your Cloudflare Worker environment variables and /etc/ash_phoenix_starter.env on your OCI VMs.


