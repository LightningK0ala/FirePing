defmodule Mix.Tasks.TestOtpEmail do
  @moduledoc """
  Mix task to test OTP email functionality.

  Usage:
  mix test_otp_email recipient@example.com [otp_code]
  """

  use Mix.Task
  alias App.Email

  @shortdoc "Test OTP email sending functionality"

  def run([]), do: run(["delivered@resend.dev", "123456"])
  def run([email]), do: run([email, "123456"])

  def run([email_address, otp_code]) do
    IO.puts("Testing OTP email sending to #{email_address} with code #{otp_code}...")

    case Email.send_otp_email(email_address, otp_code, true) do
      {:ok, response} ->
        IO.puts("✅ OTP email sent successfully!")
        IO.puts("Email ID: #{response.id}")

      {:error, reason} ->
        IO.puts("❌ OTP email failed: #{inspect(reason)}")
    end
  end

  def run(_) do
    IO.puts("Usage: mix test_otp_email recipient@example.com [otp_code]")
  end
end
