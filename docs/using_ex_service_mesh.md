Using ex_service_mesh_router instead of Caddy fits your architecture—it keeps everything BEAM-native, discovers regional nodes over Erlang distribution/Tailscale, and resolves tenant subdomains (://yourdomain.com) directly into Ash (Ash.set_tenant/1) and Ecto (repo.put_tenant/1).
Here is how to integrate ex_service_mesh_router cleanly with your Oracle Cloud VMs, Cloudflare SSL/Geo-Steering, and regional bandwidth metering.

1. SSL / TLS Architecture (Cloudflare + ex_service_mesh_router)

Because Caddy was previously handling Let's Encrypt SSL certificates on port 443, let Cloudflare terminate public HTTPS at the edge and forward traffic to your ex_service_mesh_router gateway on port 80 (or 443 with a Cloudflare Origin Certificate):
1. In Cloudflare Dashboard → SSL/TLS → Overview: Set encryption mode to Full (or Full (Strict) using a free 15-year Cloudflare Origin Certificate configured in Bandit's https: options on your gateway node).
2. In docker-compose.yml on your OCI VMs: Keep network_mode: host so ex_service_mesh_router can bind directly to port 80/443 (or 4000 behind Cloudflare Origin Rules) and communicate with your Phoenix app nodes over Tailscale (100.64.x.x).

2. Wire ClusterLifecycleWorker into AshPhoenixStarter.Application

In lib/ash_phoenix_starter/application.ex, add {Router.Shared.ClusterLifecycleWorker, []} immediately after AshPhoenixStarterWeb.Endpoint so each regional OCI node automatically registers itself with your mesh gateway on boot:
elixir
          AshPhoenixStarterWeb.Presence,
          AshPhoenixStarterWeb.Endpoint,
          {Router.Shared.ClusterLifecycleWorker, []},
          {AshAuthentication.Supervisor, [otp_app: :ash_phoenix_starter]}


3. Configure ex_service_mesh_router in config/config.exs & config/runtime.exs


In config/config.exs:

Enable Ash multi-tenancy and protect system subdomains (admin, media, api, www) from being treated as hotel tenant slugs:
elixir
config :ash_phoenix_starter, :endpoint, AshPhoenixStarterWeb.Endpoint

config :router_shared,
  app_name: :ash_phoenix_starter,
  enable_ash_tenant: true,
  enable_ecto_tenant: true,
  ecto_repo: AshPhoenixStarter.Repo,
  restricted_tenant_patterns: [
    ~r/^(www|admin|api|media|root|health)$/,
    ~r/^internal-.*$/
  ]


In config/runtime.exs:

Pass each OCI VM's Tailscale IP (NODE_IP) and the Erlang node name of your central gateway (GATEWAY_NODE) so ClusterLifecycleWorker registers the exact regional IP and port:
elixir
  if gateway_node = System.get_env("GATEWAY_NODE") do
    config :router_shared,
      gateway_node: String.to_atom(gateway_node)
  end

On each OCI VM (/etc/ash_phoenix_starter.env), add:
ini
NODE_IP=100.64.0.1
GATEWAY_NODE=gateway@100.64.0.1


4. Connect TenantResolver to Your TenantBandwidthMeter & NotificationHook

Since ex_service_mesh_router extracts the leftmost subdomain (://yourdomain.com) via Router.Shared.TenantResolver and sets Ash.set_tenant(tenant) / Router.Shared.Hooks.TenantLiveMount, update resolve_org_id in both TenantBandwidthMeter and NotificationHook to also check the resolved tenant:
elixir
  defp resolve_org_id(conn) do
    conn.assigns[:current_organization_id] ||
      get_in(conn.assigns, [:current_organization, Access.key(:id)]) ||
      conn.assigns[:tenant] ||
      conn.private[:organization_id]
  end

(If conn.assigns[:tenant] is a hotel slug string like "tucson-resort" rather than a UUID, look up the Organization ID from your TenantSettings Nebulex/ETS cache so UsageTracker always keys by org_id UUID.)

Here are both ways to run ex_service_mesh_router on your Oracle Cloud VMs—Option A (embedded inside your existing Phoenix release, zero extra containers) and Option B (a dedicated lightweight gateway container per region so you can deploy your hotel app without ever dropping edge connections).

Option A: Embedded Gateway Inside Your Existing Release (Simplest)

Best when you want a single container per VM and zero extra infrastructure to manage.
1. Add to mix.exs (deps/0):elixir
{:ex_service_mesh_router, github: "mitherealpub/ex_service_mesh_router"},
{:reverse_proxy_plug, "~> 3.0"},
{:reverse_proxy_plug_websocket, "~> 0.3.0"}

2. Start Router.Registry + Gateway Bandit on port 80 (or 443 with Cloudflare Origin Cert) in application.ex:
Your Phoenix Endpoint listens internally on 4000, while the mesh gateway listens on 80 (receiving Cloudflare proxied traffic) and routes subdomains (://yourdomain.com) to your app:elixir
children =
  timezone_cache_children() ++
    [
      # ... existing children ...
      {Router.Registry, name: Router.Registry},
      {Bandit, plug: Router.Router, port: String.to_integer(System.get_env("GATEWAY_PORT") || "80")},
      AshPhoenixStarterWeb.Presence,
      AshPhoenixStarterWeb.Endpoint,
      {Router.Shared.ClusterLifecycleWorker, []},
      {AshAuthentication.Supervisor, [otp_app: :ash_phoenix_starter]}
    ]

3. Set env vars in /etc/ash_phoenix_starter.env:ini
PORT=4000
GATEWAY_PORT=80
NODE_IP=100.64.0.1
# Leave GATEWAY_NODE unset so each regional VM acts as its own local edge gateway


Option B: Dedicated Gateway Container per Regional VM (True Zero-Downtime Edge)

Best for production scale: the gateway container stays up permanently handling HTTP/WebSocket connections while your ash_phoenix_starter app container restarts during CircleCI rolling deploys.
1. Add a gateway service to /opt/ash_phoenix_starter/docker-compose.yml on each OCI VM:yaml
services:
  gateway:
    image: ${OCIR_REGION_KEY}.ocir.io/${OCIR_NAMESPACE}/mesh-gateway:latest
    container_name: mesh_gateway
    restart: unless-stopped
    network_mode: host
    environment:
      RELEASE_DISTRIBUTION: name
      RELEASE_NODE: gateway_${OCI_REGION_NODE}@${TAILSCALE_IP}
      RELEASE_COOKIE: ${RELEASE_COOKIE}
      GATEWAY_PORT: "80"
      CLUSTER_NODES: ${CLUSTER_NODES}

  app:
    image: ${OCIR_REGION_KEY}.ocir.io/${OCIR_NAMESPACE}/${OCIR_REPO}:latest
    container_name: ash_phoenix_starter
    restart: unless-stopped
    network_mode: host
    env_file:
      - /etc/ash_phoenix_starter.env
    stop_grace_period: 30s

2. Point each regional app container to its local gateway node in /etc/ash_phoenix_starter.env:
	• On us-phoenix-1 VM (100.64.0.1):ini
PORT=4000
NODE_IP=100.64.0.1
GATEWAY_NODE=gateway_us_phoenix_1@100.64.0.1

	• On us-ashburn-1 VM (100.64.0.2):ini
PORT=4000
NODE_IP=100.64.0.2
GATEWAY_NODE=gateway_us_ashburn_1@100.64.0.2

3. How Rolling Deploys Work in Option B:
	• When CircleCI runs docker compose pull && docker compose up -d app, only the app container restarts.
	• ClusterLifecycleWorker immediately re-announces 100.64.0.1:4000 to gateway_us_phoenix_1@100.64.0.1 over local loopback/Tailscale with zero edge port drops.

Which One Should You Pick Right Now?

• Start with Option A while onboarding your first Tucson hotels—it keeps everything in a single repo and single CircleCI image build.
• Move to Option B once you have active guest traffic and want to deploy app updates without dropping active LiveView WebSockets on the edge port.
If you go with Option B, would you like a minimal Gateway.Application + Dockerfile snippet for the standalone mesh-gateway container, or are you starting with Option A first?

optionB : 
Here is the standalone mesh-gateway Elixir app (Gateway.Application + mix.exs + Dockerfile) for Option B, split into two short parts so it's easy to copy into a small gateway/ directory in your repo (or a separate repo).
Once you copy Part 1 (mix.exs + application.ex), say "next" and I'll send Part 2 (gateway/Dockerfile + the CircleCI build step).

Part 1 of 2: gateway/mix.exs & gateway/lib/gateway/application.ex


1. Create gateway/mix.exs

Define your project configuration, dependencies (ex_service_mesh_router, reverse_proxy_plug, bandit, libcluster, etc.), and application entry point:
elixir
defmodule MeshGateway.MixProject do
  use Mix.Project

  def project do
    [
      app: :mesh_gateway,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MeshGateway.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_service_mesh_router, github: "mitherealpub/ex_service_mesh_router"},
      {:reverse_proxy_plug, "~> 3.0"},
      {:reverse_proxy_plug_websocket, "~> 0.3.0"},
      {:bandit, "~> 1.8"},
      {:libcluster, "~> 3.3"}
    ]
  end
end

1. Create gateway/Dockerfile

Save this inside gateway/Dockerfile:
dockerfile
FROM elixir:1.19-slim AS builder

ENV MIX_ENV=prod \
    LANG=C.UTF-8

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app
COPY mix.exs ./
RUN mix deps.get --only prod && mix deps.compile

COPY lib ./lib
RUN mix release --overwrite

# ==========================================
# Lightweight Runtime Stage
# ==========================================
FROM debian:bookworm-slim AS runner

ENV LANG=C.UTF-8 \
    MIX_ENV=prod

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/_build/prod/rel/mesh_gateway ./

# Needs root or CAP_NET_BIND_SERVICE to bind port 80/443 on network_mode: host
CMD ["/app/bin/mesh_gateway", "start"]


2. Update CircleCI (build_and_push_ocir & Rolling Deploy)

In .circleci/config.yml, add docker build / docker push for gateway/ right below your main app image build, and update only the app service during routine rolling deploys (docker compose pull app && docker compose up -d app) so the gateway container never drops edge connections:
yaml
      - run:
          name: Build & Push Main App + Mesh Gateway to OCIR
          command: |
            APP_IMAGE="${OCIR_REGION_KEY}.ocir.io/${OCIR_NAMESPACE}/${OCIR_REPO}"
            GW_IMAGE="${OCIR_REGION_KEY}.ocir.io/${OCIR_NAMESPACE}/mesh-gateway"

            docker build --target runner -t "${APP_IMAGE}:${CIRCLE_SHA1}" -t "${APP_IMAGE}:latest" .
            docker push "${APP_IMAGE}:${CIRCLE_SHA1}"
            docker push "${APP_IMAGE}:latest"

            docker build -t "${GW_IMAGE}:${CIRCLE_SHA1}" -t "${GW_IMAGE}:latest" ./gateway
            docker push "${GW_IMAGE}:${CIRCLE_SHA1}"
            docker push "${GW_IMAGE}:latest"

And in your rolling SSH deploy step, restart gateway only if needed while rolling app cleanly:
bash
cd /opt/ash_phoenix_starter &&
docker compose pull &&
docker compose up -d gateway &&
docker compose up -d --no-deps app &&
docker image prune -f


Quick Local Test Command

Once you get back from the library, you can test the gateway + your Phoenix app together locally in two terminals using your .envrc:
• Terminal 1 (Gateway):bash
cd gateway && mix deps.get && RELEASE_NODE=gateway_us_phoenix_1@localhost iex --sname gateway_us_phoenix_1 --cookie dev_cluster_cookie_change_me -S mix
Use code with caution.
• Terminal 2 (Hotel App):bash
GATEWAY_NODE=gateway_us_phoenix_1@localhost iex --sname app_us_phoenix_1 --cooki