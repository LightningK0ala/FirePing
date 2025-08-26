defmodule AppWeb.Components.Modal do
  use AppWeb, :live_component

  def handle_event("close_modal", _params, socket) do
    # Send close event to parent component if specified
    if socket.assigns[:parent_component] do
      send_update(socket.assigns.parent_component,
        id: socket.assigns.parent_id,
        action: :close_modal
      )
    else
      # Fallback: send to parent LiveView
      send(self(), {:close_modal, socket.assigns.id})
    end

    {:noreply, socket}
  end

  def handle_event("stop_propagation", _params, socket) do
    # Do nothing - this prevents the backdrop click from firing
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div
      class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-[9999] p-4"
      phx-click="close_modal"
      phx-target={@myself}
    >
      <div
        class={[
          "bg-white dark:bg-zinc-900 rounded-lg shadow-xl w-full max-h-[90vh] overflow-y-auto",
          @max_width || "max-w-md"
        ]}
        phx-click-away="close_modal"
        phx-target={@myself}
        phx-click="stop_propagation"
      >
        <div class="p-6">
          <%= if assigns[:title] do %>
            <div class="flex items-center justify-between mb-6">
              <h2 class="text-xl font-semibold text-zinc-900 dark:text-zinc-100">
                {@title}
              </h2>
              <button
                phx-click="close_modal"
                phx-target={@myself}
                class="p-2 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded transition-colors"
                aria-label="Close modal"
              >
                ✕
              </button>
            </div>
          <% end %>

          <div class="modal-content">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
