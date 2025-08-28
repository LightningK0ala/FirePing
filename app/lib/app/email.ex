defmodule App.Email do
  @moduledoc """
  Email sending functionality using Resend API.
  """

  @doc """
  Sends an email using Resend API.

  ## Examples

      iex> Email.send_email(%{
        from: "test@fireping.app",
        to: ["user@example.com"],
        subject: "Test",
        html: "<h1>Hello</h1>"
      })
      {:ok, %{id: "email-id"}}

  """
  def send_email(params) do
    with :ok <- validate_required_fields(params),
         {:ok, response} <- send_via_resend(params) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a fire alert email to a user.

  ## Examples

      iex> Email.send_fire_alert("user@example.com", %{
        location_name: "Home",
        fire_count: 3,
        nearest_distance: 1.5
      })
      {:ok, %{id: "alert-email-id"}}

  """
  def send_fire_alert(user_email, fire_data) do
    %{
      location_name: location_name,
      fire_count: fire_count,
      nearest_distance: nearest_distance
    } = fire_data

    html_content = """
    <h2>🔥 Fire Alert for #{location_name}</h2>
    <p>We detected <strong>#{fire_count} fire(s)</strong> within your monitored area.</p>
    <p>The nearest fire is approximately <strong>#{nearest_distance} km</strong> away.</p>
    <p><em>This is an automated alert from FirePing. Please verify with official emergency services.</em></p>
    """

    email_params = %{
      from: get_fire_alert_from_email(),
      to: [user_email],
      subject: "🔥 Fire Alert: #{location_name}",
      html: html_content
    }

    send_email(email_params)
  end

  @doc """
  Sends a general email (non-fire alert) using the general from address.
  """
  def send_general_email(params) do
    params_with_from = Map.put_new(params, :from, get_general_from_email())
    send_email(params_with_from)
  end

  @doc """
  Sends an OTP authentication email to a user.

  ## Examples

      iex> Email.send_otp_email("user@example.com", "123456")
      {:ok, %{id: "otp-email-id"}}

  """
  def send_otp_email(user_email, otp_code) do
    send_otp_email(user_email, otp_code, false)
  end

  @doc """
  Sends an OTP authentication email to a user with force option.
  When force=true, bypasses SEND_EMAILS setting for admin/testing purposes.

  ## Examples

      iex> Email.send_otp_email("user@example.com", "123456", true)
      {:ok, %{id: "otp-email-id"}}

  """
  def send_otp_email(user_email, otp_code, force) do
    app_host = get_app_host()
    magic_link = "#{app_host}/verify/#{user_email}?otp=#{otp_code}"

    html_content = """
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #1f2937;">🔥 FirePing Login Code</h2>
      
      <p style="font-size: 16px; line-height: 1.5;">
        Your login code for FirePing is:
      </p>
      
      <div style="background-color: #f3f4f6; padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0;">
        <h1 style="font-size: 32px; letter-spacing: 8px; margin: 0; color: #1f2937; font-family: 'Courier New', monospace;">
          #{otp_code}
        </h1>
      </div>
      
      <p style="font-size: 16px; line-height: 1.5; text-align: center; margin: 20px 0;">
        <strong>Or click the button below to login automatically:</strong>
      </p>
      
      <div style="text-align: center; margin: 30px 0;">
        <a href="#{magic_link}" style="background-color: #3b82f6; color: white; padding: 14px 28px; text-decoration: none; border-radius: 8px; display: inline-block; font-weight: bold; font-size: 16px;">
          🚀 Login to FirePing
        </a>
      </div>
      
      <p style="font-size: 14px; color: #6b7280;">
        This code will expire in 15 minutes. If the button doesn't work, copy and paste this link into your browser:
      </p>
      
      <p style="font-size: 12px; color: #6b7280; word-break: break-all; background-color: #f9fafb; padding: 10px; border-radius: 4px;">
        #{magic_link}
      </p>
      
      <p style="font-size: 14px; color: #6b7280;">
        If you didn't request this code, you can safely ignore this email.
      </p>
      
      <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
      
      <p style="font-size: 12px; color: #9ca3af; text-align: center;">
        FirePing - Wildfire Detection & Alerts<br>
        This is an automated message, please do not reply.
      </p>
    </div>
    """

    email_params = %{
      from: get_fire_alert_from_email(),
      to: [user_email],
      subject: "🔥 Your FirePing Login Code",
      html: html_content
    }

    if force do
      send_email_forced(email_params)
    else
      send_email(email_params)
    end
  end

  defp send_email_forced(params) do
    with :ok <- validate_required_fields(params),
         {:ok, response} <- send_via_resend_forced(params) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_fields(params) do
    required_fields = [:from, :to, :subject]

    case Enum.find(required_fields, fn field -> not Map.has_key?(params, field) end) do
      nil -> :ok
      missing_field -> {:error, "Missing required field: #{missing_field}"}
    end
  end

  defp send_via_resend(params) do
    if should_send_emails?() do
      client = Resend.client(api_key: get_api_key())
      Resend.Emails.send(client, params)
    else
      # In test environment or when disabled, return mock response
      {:ok, %{id: "test-email-id-#{:rand.uniform(9999)}"}}
    end
  end

  defp send_via_resend_forced(params) do
    # Force send email regardless of SEND_EMAILS setting (for admin/testing)
    # Still respect test environment
    if Mix.env() == :test do
      {:ok, %{id: "test-email-id-#{:rand.uniform(9999)}"}}
    else
      client = Resend.client(api_key: get_api_key())
      Resend.Emails.send(client, params)
    end
  end

  defp get_api_key do
    case {Mix.env(), Application.get_env(:app, :resend_api_key), System.get_env("RESEND_API_KEY")} do
      {:test, nil, nil} -> "test_api_key"
      {_, nil, nil} -> raise "RESEND_API_KEY environment variable not set"
      {_, nil, env_key} when is_binary(env_key) -> env_key
      {_, api_key, _} when is_binary(api_key) -> api_key
    end
  end

  defp get_fire_alert_from_email do
    case {Mix.env(), Application.get_env(:app, :fire_alert_from_email),
          System.get_env("FIRE_ALERT_FROM_EMAIL")} do
      # Use test domain in test env
      {:test, _, _} -> "onboarding@resend.dev"
      # Default fallback
      {_, nil, nil} -> "noreply@fireping.net"
      {_, nil, env_email} when is_binary(env_email) -> env_email
      {_, app_email, _} when is_binary(app_email) -> app_email
    end
  end

  defp get_general_from_email do
    case {Mix.env(), Application.get_env(:app, :general_from_email),
          System.get_env("GENERAL_FROM_EMAIL")} do
      # Use test domain in test env
      {:test, _, _} -> "onboarding@resend.dev"
      # Default fallback
      {_, nil, nil} -> "support@fireping.net"
      {_, nil, env_email} when is_binary(env_email) -> env_email
      {_, app_email, _} when is_binary(app_email) -> app_email
    end
  end

  defp get_app_host do
    case {Application.get_env(:app, :app_host), System.get_env("APP_HOST")} do
      # Default fallback
      {nil, nil} -> "http://localhost:4000"
      {nil, env_host} when is_binary(env_host) -> env_host
      {app_host, _} when is_binary(app_host) -> app_host
    end
  end

  @doc """
  Checks if emails are enabled for sending.
  Public function for use by other modules.
  """
  def emails_enabled? do
    should_send_emails?()
  end

  defp should_send_emails? do
    case {Mix.env(), Application.get_env(:app, :send_emails), System.get_env("SEND_EMAILS")} do
      # Always false in test env
      {:test, _, _} -> false
      # Disabled via application config
      {_, false, _} -> false
      # Disabled via environment variable
      {_, _, "false"} -> false
      # Disabled via environment variable  
      {_, _, "0"} -> false
      # Disabled via environment variable
      {_, _, "no"} -> false
      # Default to true in non-test environments
      _ -> true
    end
  end
end
