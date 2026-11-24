defmodule Mix.Tasks.Hotel.GenPluginKeys do
  use Mix.Task
  @shortdoc "Generates an Ed25519 keypair for signing dynamic payment plugins"

  @impl Mix.Task
  def run(_args) do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    Mix.shell().info("""
    PUBLIC KEY (Set as PLUGIN_SIGNING_PUBLIC_KEY in production):
    #{Base.encode64(public_key)}

    PRIVATE KEY (Keep secret! Use with mix hotel.sign_plugin):
    #{Base.encode64(private_key)}
    """)
  end
end

defmodule Mix.Tasks.Hotel.SignPlugin do
  use Mix.Task
  @shortdoc "Signs an Elixir (.ex -> .beam) or Lua (.lua) payment plugin with Ed25519"

  @impl Mix.Task
  def run([source_path, private_key_b64]) do
    priv_key = Base.decode64!(private_key_b64)

    {runtime, mod_name, raw_payload} =
      case Path.extname(source_path) do
        ".lua" ->
          {"lua", nil, File.read!(source_path)}

        ".ex" ->
          [{module, beam_binary}] = Code.compile_file(source_path)
          {"beam", Atom.to_string(module), beam_binary}
      end

    signature =
      :crypto.sign(:eddsa, :none, raw_payload, [priv_key, :ed25519])
      |> Base.encode64()

    bundle = %{
      runtime: runtime,
      module_name: mod_name,
      payload_base64: Base.encode64(raw_payload),
      signature_b64: signature
    }

    out_path = "#{Path.basename(source_path, Path.extname(source_path))}.plugin.json"
    File.write!(out_path, Jason.encode!(bundle, pretty: true))
    Mix.shell().info("Signed #{runtime} plugin written to #{out_path}")
  end
end
