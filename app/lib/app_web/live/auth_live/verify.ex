defmodule AppWeb.AuthLive.Verify do
  use AppWeb, :live_view
  alias App.User

  def mount(%{"email" => email} = params, _session, socket) do
    otp_token = Map.get(params, "otp", "")

    socket =
      assign(socket,
        email: email,
        form: to_form(%{"otp_token" => otp_token}),
        submitting: false
      )

    # If OTP token is provided via magic link, automatically submit it after a brief delay
    case otp_token do
      "" ->
        {:ok, socket}

      otp_token ->
        Process.send_after(self(), {:auto_submit_otp, otp_token}, 1500)
        {:ok, assign(socket, submitting: true)}
    end
  end

  def handle_info({:auto_submit_otp, otp_token}, socket) do
    # Automatically submit the OTP from magic link
    handle_event("submit", %{"otp_token" => otp_token}, socket)
  end

  def handle_event("validate", %{"otp_token" => otp_token}, socket) do
    form = to_form(%{"otp_token" => otp_token})
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", %{"otp_token" => otp_token}, socket) do
    socket = assign(socket, submitting: true)

    case User.authenticate_user(socket.assigns.email, otp_token) do
      {:ok, user} ->
        {:noreply,
         socket
         |> redirect(external: "/session/login/#{user.id}")}

      {:error, :user_not_found} ->
        {:noreply,
         socket
         |> assign(submitting: false)
         |> put_flash(:error, "User not found. Please try logging in again.")
         |> push_navigate(to: ~p"/login")}

      {:error, changeset} ->
        form = to_form(changeset)
        {:noreply, assign(socket, form: form, submitting: false)}
    end
  end

  def handle_event("resend", _params, socket) do
    case App.Repo.get_by(User, email: socket.assigns.email) do
      nil ->
        {:noreply, put_flash(socket, :error, "User not found")}

      user ->
        changeset = User.generate_otp_changeset(user)

        case App.Repo.update(changeset) do
          {:ok, updated_user} ->
            # Send OTP email using the email system
            case App.Email.send_otp_email(updated_user.email, updated_user.otp_token) do
              {:ok, _} ->
                if App.Email.emails_enabled?() do
                  {:noreply, put_flash(socket, :info, "New code sent to your email!")}
                else
                  # Log OTP and magic link for development when emails are disabled
                  require Logger

                  app_host =
                    Application.get_env(:app, :app_host) || System.get_env("APP_HOST") ||
                      "http://localhost:4000"

                  magic_link =
                    "#{app_host}/verify/#{updated_user.email}?otp=#{updated_user.otp_token}"

                  Logger.info("🔐 OTP for #{updated_user.email}: #{updated_user.otp_token}")
                  Logger.info("🔗 Magic link: #{magic_link}")

                  {:noreply,
                   put_flash(socket, :info, "New code sent! Code: #{updated_user.otp_token}")}
                end

              {:error, _reason} ->
                {:noreply, put_flash(socket, :error, "Failed to send new code")}
            end

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to generate new code")}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto mt-8">
      <h1 class="text-2xl font-bold mb-4 text-zinc-900 dark:text-zinc-100">Verify Your Email</h1>

      <p class="text-gray-600 dark:text-zinc-300 mb-4">
        We sent a 6-digit code to <strong>{@email}</strong>
      </p>

      <%= if @form.data["otp_token"] != "" and @submitting do %>
        <div class="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-md p-3 mb-4">
          <p class="text-blue-700 dark:text-blue-300 text-sm flex items-center gap-2">
            <.icon name="hero-check-circle" class="h-4 w-4" /> Magic link detected - logging you in...
          </p>
        </div>
      <% end %>

      <.form for={@form} phx-submit="submit" phx-change="validate">
        <div class="mb-4">
          <label class="block text-sm font-medium mb-2 text-zinc-700 dark:text-zinc-200">
            Verification Code
          </label>
          <input
            disabled={@submitting}
            autofocus="true"
            type="text"
            name="otp_token"
            value={@form.params["otp_token"]}
            class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md text-center text-lg tracking-widest focus:border-zinc-400 focus:ring-0"
            placeholder="000000"
            maxlength="6"
            pattern="[0-9]{6}"
            required
          />

          <%= if @form.errors[:otp_token] do %>
            <p class="text-red-500 text-sm mt-1">
              {Enum.join(Keyword.get_values(@form.errors, :otp_token), ", ")}
            </p>
          <% end %>
        </div>

        <button
          type="submit"
          disabled={@submitting}
          class="w-full bg-green-500 text-white py-2 rounded-md hover:bg-green-600 mb-2 disabled:opacity-75 disabled:cursor-wait"
        >
          <%= if @submitting do %>
            <span class="inline-flex items-center justify-center gap-2">
              <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" /> Verifying...
            </span>
          <% else %>
            Verify Code
          <% end %>
        </button>
      </.form>

      <button
        phx-click="resend"
        disabled={@submitting}
        class="w-full bg-gray-500 text-white py-2 rounded-md hover:bg-gray-600 disabled:opacity-75 disabled:hover:bg-gray-500"
      >
        Resend Code
      </button>

      <p class="text-sm text-gray-600 dark:text-zinc-300 mt-4 text-center">
        <a href="/login" class="text-blue-500 hover:underline">← Back to login</a>
      </p>
    </div>
    """
  end
end
