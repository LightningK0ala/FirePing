defmodule AppWeb.AuthLive.Login do
  use AppWeb, :live_view
  alias App.{User, Email}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, to_form(%{"email" => ""}))}
  end

  def handle_event("validate", %{"email" => email}, socket) do
    form = to_form(%{"email" => email})
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", %{"email" => email}, socket) do
    case User.create_or_get_user(email) do
      {:ok, user} ->
        # Generate OTP for the user
        changeset = User.generate_otp_changeset(user)

        case App.Repo.update(changeset) do
          {:ok, updated_user} ->
            # Send OTP via email
            case Email.send_otp_email(email, updated_user.otp_token) do
              {:ok, _response} ->
                # Log OTP for development when emails are disabled
                unless Email.emails_enabled?() do
                  require Logger

                  app_host =
                    Application.get_env(:app, :app_host) || System.get_env("APP_HOST") ||
                      "http://localhost:4000"

                  magic_link = "#{app_host}/verify/#{email}?otp=#{updated_user.otp_token}"
                  Logger.info("🔐 OTP for #{email}: #{updated_user.otp_token}")
                  Logger.info("🔗 Magic link: #{magic_link}")
                end

                {:noreply,
                 socket
                 |> put_flash(:info, "Login code sent! Check your email for the 6-digit code.")
                 |> push_navigate(to: ~p"/verify/#{email}")}

              {:error, reason} ->
                require Logger
                Logger.error("Failed to send OTP email", email: email, reason: reason)

                {:noreply,
                 put_flash(socket, :error, "Failed to send login code. Please try again.")}
            end

          {:error, _changeset} ->
            {:noreply,
             put_flash(socket, :error, "Failed to generate login code. Please try again.")}
        end

      {:error, changeset} ->
        form = to_form(changeset)
        {:noreply, assign(socket, :form, form)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto mt-8">
      <h1 class="text-2xl font-bold mb-4 text-zinc-900 dark:text-zinc-100">Login to FirePing</h1>

      <.form for={@form} phx-submit="submit" phx-change="validate">
        <div class="mb-4">
          <label class="block text-sm font-medium mb-2 text-zinc-700 dark:text-zinc-200">Email</label>
          <input
            type="email"
            name="email"
            value={@form.data["email"]}
            class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
            placeholder="Enter your email"
            required
          />
        </div>

        <button
          type="submit"
          class="w-full bg-blue-500 text-white py-2 rounded-md hover:bg-blue-600"
        >
          Send Login Code
        </button>
      </.form>

      <p class="text-sm text-gray-600 dark:text-zinc-300 mt-4">
        We'll send you a 6-digit code to verify your email.
      </p>
    </div>
    """
  end
end
