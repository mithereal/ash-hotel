To tailor your Cloudflare Worker for the new multi-region, bandwidth-metered OCI setup, update your license verification response to include region_id, storage_limit_bytes, and bandwidth_limit_bytes (or pass those limits to your Phoenix app when a hotel activates its license key).
Because you didn't paste your current Worker code yet, here is a clean, drop-in pattern showing how your Worker should enrich its license payload and sync with your OCI cluster—or paste your existing Worker script and I'll update it line by line.

1. Enrich the License Key Payload in Your Cloudflare Worker

When a hotel pays and your Worker issues or validates a license key (via KV, D1, or Stripe metadata), return the hotel's assigned region_id (e.g., us-phoenix-1 for Tucson properties) alongside their plan quotas:
javascript
// Inside your Cloudflare Worker license verification / webhook handler
const PLAN_QUOTAS = {
  starter: { storage_gb: 2, bandwidth_gb: 20 },   // $1/mo tier
  growth:  { storage_gb: 10, bandwidth_gb: 100 }, // $5/mo tier
  pro:     { storage_gb: 25, bandwidth_gb: 300 }, // $10/mo tier
};

function buildLicensePayload(licenseRecord, request) {
  const tier = licenseRecord.tier || "starter";
  const quotas = PLAN_QUOTAS[tier] || PLAN_QUOTAS.starter;

  // Auto-assign nearest OCI region from Cloudflare's edge geo data if not already set
  const regionId =
    licenseRecord.region_id ||
    (request.cf?.continent === "EU" ? "eu-frankfurt-1" : "us-phoenix-1");

  return {
    valid: true,
    license_key: licenseRecord.key,
    organization_id: licenseRecord.organization_id,
    region_id: regionId,
    tier,
    storage_limit_bytes: quotas.storage_gb * 1073741824,
    bandwidth_limit_bytes: quotas.bandwidth_gb * 1073741824,
  };
}


2. Notify Your OCI Phoenix Cluster on License Creation / Upgrade

Whenever a hotel purchases or upgrades a license in your Worker, send a signed POST request to your Phoenix app (https://yourdomain.com) so your cluster immediately updates TenantUsage and calls UsageTracker.reload_limits(region_id, org_id):
javascript
async function syncLicenseToPhoenix(payload, env) {
  await fetch("https://yourdomain.com", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${env.INTERNAL_WORKER_SECRET}`,
    },
    body: JSON.stringify(payload),
  });
}


3. Phoenix Webhook Controller to Receive It

On your Elixir side, a tiny controller action receives that Worker payload, updates the hotel's TenantUsage limits in Postgres, and reloads their live Horde UsageTracker:
elixir
def update_license(conn, %{"organization_id" => org_id, "region_id" => region_id} = params) do
  # 1. Persist new limits on TenantUsage / Organization
  # 2. Reload the live Horde UsageTracker so the new limits take effect immediately
  AshPhoenixStarter.Billing.UsageTracker.reload_limits(region_id, org_id)

  Phoenix.PubSub.broadcast(
    AshPhoenixStarter.PubSub,
    "notifications:org:#{org_id}",
    {:plan_updated, params["tier"]}
  )

  json(conn, %{ok: true})
end