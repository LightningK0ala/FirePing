defmodule AppWeb.AuthLive.Verify do
  use AppWeb, :live_view
  alias App.User

  def mount(%{"email" => email}, _session, socket) do
    {:ok, assign(socket, email: email, form: to_form(%{"otp_token" => ""}))}
  end

  def handle_event("validate", %{"otp_token" => otp_token}, socket) do
    form = to_form(%{"otp_token" => otp_token})
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", %{"otp_token" => otp_token}, socket) do
    case User.authenticate_user(socket.assigns.email, otp_token) do
      {:ok, user} ->
        {:noreply,
         socket
         |> redirect(external: "/session/login/#{user.id}")}

      {:error, :user_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "User not found. Please try logging in again.")
         |> push_navigate(to: ~p"/login")}

      {:error, changeset} ->
        form = to_form(changeset)
        {:noreply, assign(socket, :form, form)}
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
            {:noreply, put_flash(socket, :info, "New code sent! Code: #{updated_user.otp_token}")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to send new code")}
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

      <.form for={@form} phx-submit="submit" phx-change="validate">
        <div class="mb-4">
          <label class="block text-sm font-medium mb-2 text-zinc-700 dark:text-zinc-200">
            Verification Code
          </label>
          <input
            autofocus="true"
            type="text"
            name="otp_token"
            value={@form.data["otp_token"]}
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
          class="w-full bg-green-500 text-white py-2 rounded-md hover:bg-green-600 mb-2 phx-submit-loading:opacity-75 phx-submit-loading:cursor-wait"
        >
          <span class="inline phx-submit-loading:hidden">Verify Code</span>
          <span class="hidden phx-submit-loading:inline-flex items-center justify-center gap-2">
            <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" /> Verifying...
          </span>
        </button>
      </.form>

      <button
        phx-click="resend"
        class="w-full bg-gray-500 text-white py-2 rounded-md hover:bg-gray-600"
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
