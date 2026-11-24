defmodule AshPhoenixStarter.Tenancy.CustomDomainResolver do
  @moduledoc """
  Nebulex-backed custom domain resolver for `Router.Shared.TenantResolver`.
  Maps custom hotel domains (e.g., "://tucsoninn.com") to their tenant slug/ID.
  """
  require Ash.Query
  alias AshPhoenixStarter.Accounts.Organization
  alias AshPhoenixStarter.Cache.TenantSettings

  @cache_ttl :timer.minutes(5)
  @negative_ttl :timer.minutes(1)

  @doc """
  Callback invoked by `Router.Shared.TenantResolver` when a host doesn't match
  a standard subdomain. Returns `{:ok, tenant_identifier}` or `:not_found`.
  """
  @spec resolve(String.t()) :: {:ok, String.t()} | :not_found
  def resolve(host) when is_binary(host) do
    normalized_host = host |> String.downcase() |> String.trim()
    cache_key = {:custom_domain, normalized_host}

    case TenantSettings.get(cache_key) do
      {:ok, tenant} ->
        {:ok, tenant}

      :not_found ->
        :not_found

      nil ->
        lookup_and_cache(normalized_host, cache_key)
    end
  end

  defp lookup_and_cache(host, cache_key) do
    # Strip leading "www." as a fallback so both "tucsoninn.com" and "://tucsoninn.com" match
    bare_host = String.replace_prefix(host, "www.", "")

    query =
      Organization
      |> Ash.Query.filter(custom_domain in [^host, ^bare_host])
      |> Ash.Query.limit(1)

    case Ash.read_one(query, authorize?: false) do
      {:ok, %Organization{} = org} ->
        # Uses `slug` if present on Organization, otherwise falls back to UUID `id`
        tenant_id = Map.get(org, :slug) || to_string(org.id)
        TenantSettings.put(cache_key, {:ok, tenant_id}, ttl: @cache_ttl)
        {:ok, tenant_id}

      _ ->
        TenantSettings.put(cache_key, :not_found, ttl: @negative_ttl)
        :not_found
    end
  end

  @doc """
  Call this when a hotel updates or removes its `custom_domain` in settings
  to invalidate the cached mapping immediately.
  """
  def invalidate(host) when is_binary(host) do
    normalized = host |> String.downcase() |> String.trim()
    bare = String.replace_prefix(normalized, "www.", "")

    TenantSettings.delete({:custom_domain, normalized})
    TenantSettings.delete({:custom_domain, "www.#{bare}"})
    :ok
  end
end
