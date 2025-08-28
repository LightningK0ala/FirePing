defmodule Mix.Tasks.TestEmail do
  @moduledoc """
  Mix task to test basic email functionality.

  Usage:
  mix test_email recipient@example.com
  """

  use Mix.Task
  alias App.Email

  @shortdoc "Test email sending functionality"

  def run([]), do: run(["test@example.com"])

  def run([email_address]) do
    IO.puts("Testing email sending to #{email_address}...")

    # Test basic email using general from address
    basic_result =
      Email.send_general_email(%{
        to: [email_address],
        subject: "FirePing Test Email",
        html:
          "<h1>Hello from FirePing!</h1><p>This is a test email to verify Resend integration is working.</p>"
      })

    case basic_result do
      {:ok, response} ->
        IO.puts("✅ Basic email sent successfully!")
        IO.puts("Email ID: #{response.id}")

      {:error, reason} ->
        IO.puts("❌ Basic email failed: #{inspect(reason)}")
    end

    IO.puts("")

    # Test fire alert email using dedicated function
    fire_alert_result =
      Email.send_fire_alert(email_address, %{
        location_name: "Test Location",
        fire_count: 3,
        nearest_distance: 2.5
      })

    case fire_alert_result do
      {:ok, response} ->
        IO.puts("✅ Fire alert email sent successfully!")
        IO.puts("Email ID: #{response.id}")

      {:error, reason} ->
        IO.puts("❌ Fire alert email failed: #{inspect(reason)}")
    end
  end

  def run(_) do
    IO.puts("Usage: mix test_email recipient@example.com")
  end
end
