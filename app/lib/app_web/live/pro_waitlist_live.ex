defmodule AppWeb.ProWaitlistLive do
  use AppWeb, :live_view
  alias App.ProInterest

  def mount(params, _session, socket) do
    plan_type = Map.get(params, "plan", "pro")

    # Store connect info during mount
    ip_address = get_connect_info(socket, :peer_data) |> get_ip()
    user_agent = get_connect_info(socket, :user_agent) || "unknown"

    socket =
      socket
      |> assign(:plan_type, plan_type)
      |> assign(:form, to_form(ProInterest.changeset(%ProInterest{plan_type: plan_type}, %{})))
      |> assign(:success, false)
      |> assign(:waitlist_count, ProInterest.count_by_plan(plan_type))
      |> assign(:ip_address, ip_address)
      |> assign(:user_agent, user_agent)

    {:ok, socket}
  end

  def handle_event("join_waitlist", %{"pro_interest" => params}, socket) do
    # Add some metadata using stored assigns
    enhanced_params =
      params
      |> Map.put("source_page", "pricing_page")
      |> Map.put("ip_address", socket.assigns.ip_address)
      |> Map.put("user_agent", socket.assigns.user_agent)

    case ProInterest.create_interest(enhanced_params) do
      {:ok, _interest} ->
        socket =
          socket
          |> assign(:success, true)
          |> assign(:waitlist_count, ProInterest.count_by_plan(socket.assigns.plan_type))

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("validate", %{"pro_interest" => params}, socket) do
    changeset = ProInterest.changeset(%ProInterest{}, params)
    {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}
  end

  defp get_ip(peer_data) when is_tuple(peer_data) do
    peer_data |> elem(0) |> :inet.ntoa() |> to_string()
  rescue
    _ -> "unknown"
  end

  defp get_ip(_), do: "unknown"

  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto bg-white dark:bg-zinc-900 rounded-2xl p-6 shadow-xl border border-zinc-200 dark:border-zinc-700">
      <%= if @success do %>
        <!-- Success State -->
        <div class="text-center">
          <div class="w-16 h-16 bg-gradient-to-r from-green-500 to-emerald-600 rounded-full flex items-center justify-center text-white text-2xl mx-auto mb-4">
            ✓
          </div>
          <h3 class="text-xl font-bold text-zinc-900 dark:text-zinc-100 mb-2">
            You're on the list!
          </h3>
          <p class="text-zinc-600 dark:text-zinc-300 mb-4">
            We'll email you as soon as {String.capitalize(@plan_type)} launches.
          </p>
          <div class="bg-zinc-100 dark:bg-zinc-800 rounded-lg p-3">
            <p class="text-sm text-zinc-600 dark:text-zinc-400">
              <span class="font-semibold">{@waitlist_count}</span>
              people waiting for {String.capitalize(@plan_type)}
            </p>
          </div>
        </div>
      <% else %>
        <!-- Form State -->
        <div class="text-center mb-6">
          <h3 class="text-xl font-bold text-zinc-900 dark:text-zinc-100 mb-2">
            Join the {String.capitalize(@plan_type)} Waitlist
          </h3>
          <p class="text-zinc-600 dark:text-zinc-300 text-sm">
            Get early access and exclusive launch pricing
          </p>
        </div>

        <.form for={@form} phx-submit="join_waitlist" phx-change="validate" class="space-y-4">
          <div>
            <.input
              field={@form[:email]}
              type="email"
              placeholder="your@email.com"
              required
              class="w-full"
            />
          </div>

          <div>
            <.input
              field={@form[:message]}
              type="textarea"
              placeholder="Tell us what you'd use FirePing for (optional)"
              rows="3"
              class="w-full"
            />
          </div>

          <input type="hidden" name="pro_interest[plan_type]" value={@plan_type} />

          <button
            type="submit"
            class="w-full bg-gradient-to-r from-orange-500 to-red-600 text-white font-semibold py-3 px-6 rounded-xl hover:shadow-lg transition-all duration-300"
          >
            Join Waitlist
          </button>
        </.form>

        <%= if @waitlist_count > 0 do %>
          <div class="mt-4 text-center">
            <p class="text-xs text-zinc-500 dark:text-zinc-400">
              <span class="font-semibold">{@waitlist_count}</span> people already waiting
            </p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
