defmodule Mix.Tasks.Generate.WebhookKeys do
  @moduledoc """
  Generates Ed25519 keypairs for webhook signature generation and verification.

  ## Usage

      mix generate.webhook.keys

  This will generate a new Ed25519 keypair and output the base64-encoded keys
  that can be used in your .env file for WEBHOOK_PRIVATE_KEY and WEBHOOK_PUBLIC_KEY.

  ## Example output

      WEBHOOK_PRIVATE_KEY=mlrAtR18R96Vm39nXsGXxCS/5nqs45YTDdljV/eaxh4=
      WEBHOOK_PUBLIC_KEY=HY9a5C20R0I/ErKfoP1cwYUnBoFrk0InBWEDfIXphmI=

  Copy these values to your .env file.
  """

  use Mix.Task

  @shortdoc "Generate Ed25519 webhook keypairs"

  @impl Mix.Task
  def run(_args) do
    # Generate a new Ed25519 keypair
    {private_key, public_key} = Ed25519.generate_key_pair()

    # Encode keys as base64
    private_key_b64 = Base.encode64(private_key)
    public_key_b64 = Base.encode64(public_key)

    # Output the keys in a format that can be easily copied to .env
    IO.puts("")
    IO.puts("Generated Ed25519 webhook keypair:")
    IO.puts("")
    IO.puts("WEBHOOK_PRIVATE_KEY=#{private_key_b64}")
    IO.puts("WEBHOOK_PUBLIC_KEY=#{public_key_b64}")
    IO.puts("")
    IO.puts("Copy these lines to your .env file.")
    IO.puts("")
    IO.puts("Note: Keep your private key secure and never share it publicly.")
    IO.puts("The public key can be shared with webhook recipients for signature verification.")
    IO.puts("")
  end
end
