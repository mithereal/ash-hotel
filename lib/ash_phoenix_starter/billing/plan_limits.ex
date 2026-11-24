defmodule AshPhoenixStarter.Billing.PlanLimits do
  @moduledoc """
  Maps Bling / Stripe subscription price IDs ($1-$10/mo tiers) to monthly
  storage and guest-viewing bandwidth allowances.
  """

  @gb 1_073_741_824

  # Fallback defaults (e.g., $1/mo Starter tier: 2 GB storage, 20 GB bandwidth)
  @starter_limits {2 * @gb, 20 * @gb}
  # $5/mo Growth tier: 10 GB storage, 100 GB bandwidth
  @growth_limits {10 * @gb, 100 * @gb}
  # $10/mo Pro Hotel tier: 25 GB storage, 300 GB bandwidth
  @pro_limits {25 * @gb, 300 * @gb}

  @doc """
  Returns `{storage_limit_bytes, bandwidth_limit_bytes}` for an organization's
  active Bling subscription price ID.
  """
  def limits_for_price(price_id) do
    cond do
      price_id == System.get_env("STRIPE_PRICE_PRO") -> @pro_limits
      price_id == System.get_env("STRIPE_PRICE_GROWTH") -> @growth_limits
      true -> @starter_limits
    end
  end
end
