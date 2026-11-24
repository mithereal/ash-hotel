# lib/ash_phoenix_starter/accounts/user_organization/validations/enforce_member_limit.ex
defmodule AshPhoenixStarter.Accounts.UserOrganization.Validations.EnforceMemberLimit do
  use Ash.Resource.Validation

  alias AshPhoenixStarter.Accounts.{Organization, UserOrganization}
  alias AshPhoenixStarter.Licensing.Verifier

  require Ash.Query

  @tier_member_limits %{
    "basic" => 3,
    "plus" => 15,
    "pro" => 50,
    "enterprise" => :unlimited
  }

  @impl true
  def validate(changeset, _opts, context) do
    organization_id = resolve_organization_id(changeset, context)

    if is_nil(organization_id) do
      :ok
    else
      with {:ok, organization} <- load_organization_with_owner(organization_id),
           {:ok, limit} <- resolve_member_limit(organization),
           {:ok, current_count} <- count_organization_members(organization.id) do
        if limit == :unlimited or current_count < limit do
          :ok
        else
          {:error,
           field: :base,
           message:
             "Organization member limit reached (#{current_count}/#{limit}) for your current license tier."}
        end
      else
        {:error, reason} when is_atom(reason) ->
          {:error, field: :base, message: "License validation failed (#{reason})."}

        {:error, reason} when is_binary(reason) ->
          {:error, field: :base, message: reason}

        {:error, error} ->
          {:error, error}

        _other ->
          {:error, field: :base, message: "Unable to verify organization member license limit."}
      end
    end
  end

  defp resolve_organization_id(changeset, context) do
    Ash.Changeset.get_attribute(changeset, :organization_id) ||
      case Map.get(context, :actor) do
        %{organization: %{id: id}} ->
          id

        %{current_organization: domain} when is_binary(domain) ->
          case Ash.get(Organization, [domain: domain], authorize?: false) do
            {:ok, organization} -> organization.id
            _ -> nil
          end

        _ ->
          nil
      end
  end

  defp load_organization_with_owner(organization_id) do
    with {:ok, organization} <- Ash.get(Organization, organization_id, authorize?: false) do
      Ash.load(organization, [:owner], authorize?: false)
    end
  end

  defp resolve_member_limit(organization) do
    owner_email = organization.owner && organization.owner.email

    license_key =
      organization.license_key ||
        (organization.owner && organization.owner.license_key) ||
        Application.get_env(:AshPhoenixStarter, :license_key) ||
        System.get_env("LICENSE_KEY")

    case Verifier.verify(license_key, expected_email: owner_email) do
      {:ok, %{tier: tier}} ->
        normalized_tier = tier |> to_string() |> String.trim() |> String.downcase()
        {:ok, Map.get(@tier_member_limits, normalized_tier, 3)}

      {:error, :missing_license} ->
        {:ok, 3}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_organization_members(organization_id) do
    query =
      UserOrganization
      |> Ash.Query.filter(organization_id == ^organization_id)

    case Ash.count(query, authorize?: false) do
      {:ok, count} -> {:ok, count}
      {:error, error} -> {:error, error}
    end
  end
end
