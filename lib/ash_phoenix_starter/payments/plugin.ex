defmodule AshPhoenixStarter.Payments.Plugin do
  use Ash.Resource,
    domain: AshPhoenixStarter.Payments.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "payment_plugins"
    repo AshPhoenixStarter.Repo
  end

  actions do
    defaults [:read]

    read :active_plugins do
      filter expr(active == true)
    end

    create :install_signed do
      accept [:runtime, :module_name, :code_payload, :signature_b64, :version]
      upsert? true
      upsert_identity :unique_provider_id

      change fn changeset, _ctx ->
        runtime = Ash.Changeset.get_attribute(changeset, :runtime)
        mod_name = Ash.Changeset.get_attribute(changeset, :module_name)
        payload = Ash.Changeset.get_attribute(changeset, :code_payload)
        sig_b64 = Ash.Changeset.get_attribute(changeset, :signature_b64)

        case Hotel.Payments.PluginLoader.verify_and_load(runtime, mod_name, payload, sig_b64) do
          {:ok, meta} ->
            changeset
            |> Ash.Changeset.force_change_attribute(:provider_id, meta.id)
            |> Ash.Changeset.after_action(fn _cs, plugin ->
              Hotel.Payments.ClusterSync.broadcast_plugin_installed(
                plugin.runtime,
                plugin.module_name,
                plugin.code_payload,
                plugin.signature_b64
              )

              {:ok, plugin}
            end)

          {:error, reason} ->
            Ash.Changeset.add_error(changeset,
              field: :code_payload,
              message: "Rejected: #{inspect(reason)}"
            )
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :super_admin)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :provider_id, :string, allow_nil?: false, public?: true

    attribute :runtime, :atom,
      constraints: [one_of: [:beam, :lua]],
      default: :beam,
      allow_nil?: false,
      public?: true

    attribute :module_name, :string, public?: true
    attribute :code_payload, :binary, allow_nil?: false, sensitive?: true
    attribute :signature_b64, :string, allow_nil?: false, public?: true
    attribute :version, :string, default: "1.0.0", public?: true
    attribute :active, :boolean, default: true, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_provider_id, [:provider_id]
  end
end
