defmodule AppWeb.AuthLive.Login do
  use AppWeb, :live_view
  alias App.User

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
            # In a real app, you'd send the OTP via email here
            # For now, we'll just show it in the flash
            {:noreply,
             socket
             |> put_flash(:info, "OTP sent! Code: #{updated_user.otp_token}")
             |> push_navigate(to: ~p"/verify/#{email}")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to generate OTP")}
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
