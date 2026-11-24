defmodule AshPhoenixStarter.Payments.PluginLoader do
  alias AshPhoenixStarter.Payments.{Plugin, Registry}

  @allowed_namespace ~r/^Elixir\.AshPhoenixStarter\.Payments\.Plugins\.[A-Z][A-Za-z0-9_]*$/
  @required_callbacks [
    {:metadata, 0},
    {:config_schema, 0},
    {:authorize, 3},
    {:capture, 2},
    {:void, 2},
    {:refund, 3},
    {:handle_webhook, 3}
  ]

  def verify_and_load_memory(module_name_str, beam_binary, signature_b64) do
    with :ok <- validate_namespace(module_name_str),
         :ok <- verify_signature(beam_binary, signature_b64),
         mod_atom = String.to_atom(module_name_str),
         {:module, ^mod_atom} <- :code.load_binary(mod_atom, ~c"signed_plugin.beam", beam_binary),
         :ok <- verify_behaviour(mod_atom) do
      Registry.register_module(mod_atom)
    end
  end

  def load_persisted_plugins do
    Plugin
    |> Ash.Query.for_read(:active_plugins)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn plugin ->
      verify_and_load_memory(plugin.module_name, plugin.beam_binary, plugin.signature_b64)
    end)
  end

  defp validate_namespace(name) do
    if Regex.match?(@allowed_namespace, name), do: :ok, else: {:error, :invalid_plugin_namespace}
  end

  defp verify_signature(beam_binary, signature_b64) do
    pub_key_b64 = Application.fetch_env!(:AshPhoenixStarter, :plugin_signing_public_key)

    with {:ok, pub_key} <- Base.decode64(pub_key_b64),
         {:ok, sig} <- Base.decode64(signature_b64),
         true <- :crypto.verify(:eddsa, :none, beam_binary, sig, [pub_key, :ed25519]) do
      :ok
    else
      _ -> {:error, :invalid_plugin_signature}
    end
  end

  defp verify_behaviour(module) do
    missing = Enum.reject(@required_callbacks, fn {f, a} -> function_exported?(module, f, a) end)
    if missing == [], do: :ok, else: {:error, {:missing_callbacks, missing}}
  end
end
