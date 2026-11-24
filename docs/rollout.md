With 1,000–6,000 production hotels paying $1–$10/month, start with a lean 3-node Oracle Cloud Ampere ARM (VM.Standard.A1.Flex) topology connected over Tailscale, and add regional VMs only as specific geographic regions gain paying hotels.
Because Elixir/Phoenix handles thousands of concurrent WebSockets per core and your media traffic is offloaded to OCI Object Storage + Cloudflare, you do not need a large fleet on day one.

1. Recommended Machine Layout (Phase 1 vs. Growth Phase)


Role	OCI Region	OCI VM Shape	Specs	Monthly Cost Est.
Primary App + Postgres (or Managed OCI Postgres)	US-Ashburn (us-ashburn-1)	VM.Standard.A1.Flex	4 OCPUs, 24 GB RAM	$0 (within OCI Always Free 4 OCPU / 24 GB limit)
Regional App Node (Americas West / Backup)	US-Phoenix (us-phoenix-1)	VM.Standard.A1.Flex	2 OCPUs, 12 GB RAM	~$15–$25/mo
Regional App Node (Europe)	EU-Frankfurt (eu-frankfurt-1)	VM.Standard.A1.Flex	2 OCPUs, 12 GB RAM	~$15–$25/mo
Regional App Node (APAC — add when needed)	AP-Tokyo (ap-tokyo-1)	VM.Standard.A1.Flex	2 OCPUs, 12 GB RAM	~$15–$25/mo

• Why Ampere A1 (ARM64): OCI's Ampere A1 instances offer the best price-to-performance ratio for the BEAM (Elixir/Erlang scales linearly across ARM cores), and your first 4 OCPUs + 24 GB RAM are covered under OCI's Always Free tier.
• Keep Postgres in one central region (with read replicas later): Run your primary PostgreSQL database in US-Ashburn (either on a dedicated VM with NVMe block volume or OCI Managed PostgreSQL). Since UsageTracker buffers bandwidth/storage counters in memory and flushes to Postgres only once every 60 seconds, cross-region DB writes stay tiny and fast.

2. Networking Topology: Tailscale Mesh Over Public Internet

Instead of configuring complex OCI cross-region VCN peering and dynamic routing gateways (DRGs), connect your regional VMs using Tailscale (WireGuard mesh):
1. Install Tailscale on every OCI VM and tag them (tag:oci-phoenix). Each VM gets a static private mesh IP (100.x.y.z) and encrypted node-to-node traffic automatically.
2. Name each node by its OCI region in /etc/ash_phoenix_starter.env so your RegionalDistribution Horde strategy pins hotels to their local VM:
	• Ashburn VM: RELEASE_NODE=app_us_ashburn_1@100.64.0.1
	• Phoenix VM: RELEASE_NODE=app_us_phoenix_1@100.64.0.2
	• Frankfurt VM: RELEASE_NODE=app_eu_frankfurt_1@100.64.0.3
3. Lock down Erlang ports (4369 and 9000–9100) to tailscale0 only (100.64.0.0/10), leaving only ports 80 and 443 open to the public internet for Caddy.

3. Traffic Routing: GeoDNS + Cloudflare CDN

Put Cloudflare in front of both your application domain (yourdomain.com) and your media domain (://yourdomain.com):
• Geo-Steering for Guests (yourdomain.com): Use Cloudflare Load Balancing (Geo-Steering) to route visitors based on their continent/region directly to the nearest OCI VM (e.g., European travelers hit the Frankfurt VM; North American travelers hit Ashburn or Phoenix).
• Zero-Egress Media Delivery (://yourdomain.com): Point your media subdomain to your OCI Object Storage bucket. Because OCI and Cloudflare are Bandwidth Alliance partners, egress from OCI Object Storage to Cloudflare is $0, keeping you well under OCI's 10 TB/month free egress limit even at 6,000 hotels.

4. Step-by-Step Rollout Order

1. Launch 1 VM in US-Ashburn + 1 VM in EU-Frankfurt (plus Postgres in Ashburn) to verify multi-region libcluster and Horde failover before onboarding hotels.
2. Configure Cloudflare Geo-Steering to route Americas traffic to Ashburn and EMEA/APAC traffic to Frankfurt.
3. Monitor your RegionAdminLive dashboard (/admin/regions)—once a new region (like APAC or South America) reaches ~50–100 paying hotels, spin up an A1 VM in that OCI region, add its Tailscale IP to CLUSTER_NODES and OCI_NODES in CircleCI, and deploy.

Since your first target hotels are in Tucson, AZ, anchor your primary infrastructure in OCI US-Phoenix (us-phoenix-1)—it is right next door to Tucson (~100 miles away), giving your local hotels and guests single-digit millisecond latency, and place your OCI Database with PostgreSQL (Managed) in that exact same VCN.

1. Recommended Machine & Database Topology


Component	OCI Region	Shape / Tier	Specs	Purpose & Cost
Primary App VM (Southwest / Tucson)	US-Phoenix (us-phoenix-1)	VM.Standard.A1.Flex	4 OCPUs, 24 GB RAM	Handles Tucson/West Coast hotels + guests ($0 on OCI Always Free tier)
OCI Managed PostgreSQL	US-Phoenix (us-phoenix-1)	Flexible / Standard Compute	2 OCPUs, 32 GB RAM, 100 GB NVMe	Automated backups, zero DB maintenance, ultra-low latency to Phoenix VM
Secondary App VM (East Coast / Failover)	US-Ashburn (us-ashburn-1)	VM.Standard.A1.Flex	2 OCPUs, 12 GB RAM	Handles East Coast hotels + automatic Horde failover (~$15–$25/mo)
Regional App VM (Europe — add when needed)	EU-Frankfurt (eu-frankfurt-1)	VM.Standard.A1.Flex	2 OCPUs, 12 GB RAM	Add once you onboard European properties

• Colocate your Primary App VM and Managed Postgres in us-phoenix-1: Put both in the same VCN (with Managed Postgres in a Private Subnet) so database queries stay inside OCI's local data center network at <1 ms latency and zero egress cost.
• OCI Object Storage Bucket in us-phoenix-1: Create your primary media bucket (hotel-media-prod) in us-phoenix-1 as well, fronted by Cloudflare (STORAGE_CDN_URL) for free Bandwidth Alliance egress.

2. Networking & Security Setup

1. US-Phoenix VCN Layout:
	• Public Subnet (10.0.1.0/24): Hosts your us-phoenix-1 Ampere VM (ports 80 and 443 open for Caddy).
	• Private Subnet (10.0.2.0/24): Hosts your OCI Managed PostgreSQL instance. Add a Security List ingress rule allowing TCP port 5432 only from 10.0.1.0/24 and your Tailscale CIDR (100.64.0.0/10).
2. Tailscale Mesh Across Regions:
	• Install Tailscale on both the us-phoenix-1 VM (100.64.0.1) and us-ashburn-1 VM (100.64.0.2), and enable Tailscale subnet routing (--advertise-routes=10.0.2.0/24) on the Phoenix VM so the Ashburn VM can reach your private Managed Postgres database securely over WireGuard without exposing port 5432 to the public internet.
3. Node Naming for Horde Regional Pinning:
	• Phoenix VM: RELEASE_NODE=app_us_phoenix_1@100.64.0.1
	• Ashburn VM: RELEASE_NODE=app_us_ashburn_1@100.64.0.2

(Set POOL_SIZE=15 on Phoenix and POOL_SIZE=10 on Ashburn—well within OCI Managed PostgreSQL's default max_connections limit.)

Tailscale Mesh & Subnet Router Setup so your us-phoenix-1 and us-ashburn-1 VMs form an encrypted libcluster + Horde mesh and your Ashburn VM reaches your private OCI Managed PostgreSQL instance securely without opening port 5432 to the public internet.
Once you run these commands on your two VMs, say "next" and I'll send Part 2 of 2: Cloudflare Geo-Steering & Bandwidth Alliance Setup.

Step 1: Configure Your us-phoenix-1 VM as a Tailscale Subnet Router

SSH into your US-Phoenix VM (which sits in the same VCN as your OCI Managed PostgreSQL private subnet 10.0.2.0/24) and run:
bash
# 1. Install Tailscale
curl -fsSL https://tailscale.com | sh

# 2. Enable IP forwarding so Phoenix can route traffic from Ashburn to OCI Managed Postgres
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# 3. Connect and advertise your OCI Private Subnet CIDR (replace 10.0.2.0/24 with your actual DB subnet CIDR)
sudo tailscale up --advertise-routes=10.0.2.0/24 --accept-dns=false

(Open your Tailscale Admin Console → Machines, click the ... menu on your Phoenix VM → Edit route settings, and approve the 10.0.2.0/24 subnet route.)

Step 2: Connect Your us-ashburn-1 VM (and Future Regional VMs)

SSH into your US-Ashburn VM and run:

bash```
curl -fsSL https://tailscale.com | sh
sudo tailscale up --accept-routes --accept-dns=false

• Because --accept-routes is enabled, your Ashburn VM can now connect directly to your Phoenix Managed Postgres private IP (e.g., 10.0.2.15:5432) over WireGuard.
• Lock down iptables on both VMs so Erlang distribution (4369 and 9000–9100) only accepts traffic arriving on the tailscale0 interface:
```

bash```
sudo iptables -I INPUT 1 -i tailscale0 -p tcp --dport 4369 -j ACCEPT
sudo iptables -I INPUT 1 -i tailscale0 -p tcp --dport 9000:9100 -j ACCEPT
sudo netfilter-persistent save

```

Cloudflare Geo-Steering & Bandwidth Alliance Setup so guests in Tucson/West Coast hit your us-phoenix-1 VM, East Coast guests hit us-ashburn-1, and all property photos stream from OCI Object Storage with $0 egress fees.

Step 1: Set Up Zero-Egress Media Delivery (://yourdomain.com)

Oracle Cloud and Cloudflare are Bandwidth Alliance partners, meaning data transferred from OCI Object Storage to Cloudflare's CDN is completely free.
1. Create a Public Read Bucket in OCI (us-phoenix-1):
	• In OCI Console → Storage → Buckets, create hotel-media-prod with Visibility: Public (or keep it private if you prefer Cloudflare Worker signing, though Public Read with unguessable UUID/hotel paths is fastest).
	• Note your OCI Object Storage URL format:
https://<namespace>://<namespace>/b/hotel-media-prod/o/
2. Add a CNAME Record in Cloudflare DNS:
	• Type: CNAME
	• Name: media (for ://yourdomain.com)
	• Target: <namespace>.objectstorage.us-phoenix-1.oci.customer-oci.com
	• Proxy status: Proxied (Orange Cloud ON)
3. Add a Cloudflare Transform Rule (URL Rewrite):
	• Because OCI's native public URL expects /n/<namespace>/b/<bucket>/o/<key>, add a single Transform Rule → Rewrite URL in Cloudflare for http.host eq "://yourdomain.com":
		• Path Rewrite (Dynamic): concat("/n/<namespace>/b/hotel-media-prod/o", http.request.uri.path)
4. Set STORAGE_CDN_URL=https://yourdomain.com in /etc/ash_phoenix_starter.env on both VMs.

Step 2: Route Guests by Region with Cloudflare Load Balancing (Geo-Steering)

To route Tucson/Southwest/West Coast visitors to us-phoenix-1 and East Coast/European visitors to us-ashburn-1 (with automatic health-check failover if either VM restarts during a deploy):
1. Create Two Origin Pools in Cloudflare (Traffic → Load Balancing):
	• pool-us-phoenix: Public IP of your us-phoenix-1 VM (port 443).
	• pool-us-ashburn: Public IP of your us-ashburn-1 VM (port 443).
	• Attach an HTTPS Health Check (GET /, expected status 200) to both pools.
2. Create a Geo-Steering Load Balancer (yourdomain.com & *.yourdomain.com):
	• Default / Fallback Pool: pool-us-phoenix (then pool-us-ashburn).
	• Region Steering Rules:
		• Western North America (WNAM): pool-us-phoenix (Primary), pool-us-ashburn (Fallback) — keeps Tucson hotels and local guests on the Phoenix VM (<10 ms).
		• Eastern North America (ENAM) & Western Europe (WEU): pool-us-ashburn (Primary), pool-us-phoenix (Fallback).
3. Enable WebSockets in Cloudflare:
	• Go to Network → WebSockets and confirm it is ON (enabled by default) so Phoenix LiveView connects smoothly through Cloudflare.

Final Architecture Recap

• Tucson & West Coast Hotels/Guests → Cloudflare (WNAM) → OCI us-phoenix-1 VM → OCI Managed Postgres (us-phoenix-1) (<1 ms DB latency).
• East Coast & EU Guests → Cloudflare (ENAM/WEU) → OCI us-ashburn-1 VM → Tailscale WireGuard Mesh → OCI Managed Postgres.
• Property Photos & WebP Thumbnails → Browser uploads directly via presigned URL to OCI Object Storage → Guests view via Cloudflare (://yourdomain.com) at $0 egress cost.
