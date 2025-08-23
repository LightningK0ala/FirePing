defmodule AppWeb.Components.NotificationDevices do
  use AppWeb, :live_component

  alias App.{Notifications, WebPush}

  def update(assigns, socket) do
    devices = Notifications.list_notification_devices(assigns.current_user.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:devices, devices)
     |> assign(:show_add_form, false)
     |> assign(:loading_test, nil)}
  end

  def handle_event("show_add_form", _params, socket) do
    {:noreply, assign(socket, :show_add_form, true)}
  end

  def handle_event("hide_add_form", _params, socket) do
    {:noreply, assign(socket, :show_add_form, false)}
  end

  def handle_event("delete_device", %{"device_id" => device_id}, socket) do
    case Notifications.get_user_notification_device(socket.assigns.current_user.id, device_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        case Notifications.delete_notification_device(device) do
          {:ok, _} ->
            devices = Notifications.list_notification_devices(socket.assigns.current_user.id)

            {:noreply,
             socket
             |> assign(:devices, devices)
             |> put_flash(:info, "Device removed successfully")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove device")}
        end
    end
  end

  def handle_event("toggle_device", %{"device_id" => device_id}, socket) do
    case Notifications.get_user_notification_device(socket.assigns.current_user.id, device_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        case Notifications.update_notification_device(device, %{active: !device.active}) do
          {:ok, _} ->
            devices = Notifications.list_notification_devices(socket.assigns.current_user.id)
            status = if device.active, do: "disabled", else: "enabled"

            {:noreply,
             socket
             |> assign(:devices, devices)
             |> put_flash(:info, "Device #{status} successfully")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update device")}
        end
    end
  end

  def handle_event("send_test_notification", %{"device_id" => device_id}, socket) do
    # Start loading state
    socket = assign(socket, :loading_test, device_id)

    # Send message to parent to handle the async operation
    send(self(), {:send_test_notification, device_id})

    # Clear loading state after a timeout as a fallback
    Process.send_after(self(), {:clear_test_loading, device_id}, 5000)

    {:noreply, socket}
  end

  def handle_info({:clear_test_loading, device_id}, socket) do
    if socket.assigns.loading_test == device_id do
      {:noreply, assign(socket, :loading_test, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("register_web_push", params, socket) do
    device_attrs = %{
      user_id: socket.assigns.current_user.id,
      name: params["name"],
      channel: "web_push",
      config: %{
        "endpoint" => params["endpoint"],
        "keys" => %{
          "p256dh" => params["p256dh"],
          "auth" => params["auth"]
        }
      },
      user_agent: params["user_agent"]
    }

    case Notifications.create_notification_device(device_attrs) do
      {:ok, _device} ->
        # Refresh the device list after successful registration
        devices = Notifications.list_notification_devices(socket.assigns.current_user.id)

        {:noreply,
         socket
         |> assign(:devices, devices)
         |> assign(:show_add_form, false)
         |> put_flash(:info, "Device registered successfully!")}

      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {field, {message, _}} -> "#{field} #{message}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Registration failed: #{error_msg}")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
      <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
        <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Notification Devices</h2>
      </div>
      <div class="p-4">
        <%= if Enum.empty?(@devices) do %>
          <div class="text-center py-8">
            <div class="text-4xl mb-2">📱</div>
            <div class="text-zinc-500 dark:text-zinc-400 mb-4">No devices registered</div>
            <button
              phx-click="show_add_form"
              phx-target={@myself}
              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700 transition-colors"
            >
              Register Your First Device
            </button>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for device <- @devices do %>
              <div class="p-3 border border-zinc-200 dark:border-zinc-700 rounded-lg">
                <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="flex flex-wrap items-center gap-2 mb-1">
                      <span class="font-medium text-zinc-900 dark:text-zinc-100 truncate">
                        {device.name}
                      </span>
                      <%= if device.channel == "web_push" do %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400 flex-shrink-0">
                          Web Push
                        </span>
                      <% end %>
                      <%= if device.active do %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400 flex-shrink-0">
                          Active
                        </span>
                      <% else %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300 flex-shrink-0">
                          Disabled
                        </span>
                      <% end %>
                    </div>
                    <%= if device.last_used_at do %>
                      <div class="text-xs text-zinc-500 dark:text-zinc-400">
                        Last used: {Calendar.strftime(device.last_used_at, "%B %d, %Y at %I:%M %p")}
                      </div>
                    <% end %>
                  </div>
                  <div class="flex flex-wrap items-center gap-2 sm:flex-nowrap">
                    <button
                      phx-click="send_test_notification"
                      phx-value-device_id={device.id}
                      phx-target={@myself}
                      disabled={!device.active or @loading_test == device.id}
                      class="flex-1 sm:flex-none px-3 py-1.5 text-xs font-medium text-blue-600 hover:text-blue-700 disabled:opacity-50 disabled:cursor-not-allowed border border-blue-200 dark:border-blue-700 rounded hover:bg-blue-50 dark:hover:bg-blue-950/20 transition-colors"
                    >
                      <%= if @loading_test == device.id do %>
                        <div class="inline-block animate-spin rounded-full h-3 w-3 border border-blue-600 border-b-transparent mr-1">
                        </div>
                        Sending...
                      <% else %>
                        Test
                      <% end %>
                    </button>
                    <button
                      phx-click="toggle_device"
                      phx-value-device_id={device.id}
                      phx-target={@myself}
                      class="flex-1 sm:flex-none px-3 py-1.5 text-xs font-medium text-amber-600 hover:text-amber-700 border border-amber-200 dark:border-amber-700 rounded hover:bg-amber-50 dark:hover:bg-amber-950/20 transition-colors"
                    >
                      {if device.active, do: "Disable", else: "Enable"}
                    </button>
                    <button
                      phx-click="delete_device"
                      phx-value-device_id={device.id}
                      phx-target={@myself}
                      data-confirm="Are you sure you want to remove this device?"
                      class="flex-1 sm:flex-none px-3 py-1.5 text-xs font-medium text-red-600 hover:text-red-700 border border-red-200 dark:border-red-700 rounded hover:bg-red-50 dark:hover:bg-red-950/20 transition-colors"
                    >
                      Remove
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <div class="mt-4 pt-4 border-t border-zinc-200 dark:border-zinc-700">
            <button
              phx-click="show_add_form"
              phx-target={@myself}
              class="w-full sm:w-auto inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-blue-600 hover:text-blue-700 border border-blue-200 dark:border-blue-700 rounded-md hover:bg-blue-50 dark:hover:bg-blue-950/20 transition-colors"
            >
              + Add Another Device
            </button>
          </div>
        <% end %>

        <%= if @show_add_form do %>
          <div class="mt-4 p-4 sm:p-6 border border-blue-200 dark:border-blue-700 bg-blue-50 dark:bg-blue-950/50 rounded-lg">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-medium text-zinc-900 dark:text-zinc-100">Register Web Push Device</h3>
              <button
                phx-click="hide_add_form"
                phx-target={@myself}
                class="p-1 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded transition-colors"
              >
                ✕
              </button>
            </div>

            <div
              id="web-push-registration"
              phx-hook="WebPushRegistration"
              data-phx-target={@myself}
              data-vapid-key={WebPush.get_vapid_public_key() || ""}
            >
              <div class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2">
                    Device Name
                  </label>
                  <input
                    type="text"
                    id="device-name"
                    placeholder="My Phone, Chrome Browser, etc."
                    class="w-full px-3 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-blue-400 focus:ring-1 focus:ring-blue-400 text-sm"
                  />
                </div>

                <div>
                  <button
                    id="register-push-button"
                    type="button"
                    class="w-full inline-flex items-center justify-center px-4 py-3 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                  >
                    Enable Push Notifications
                  </button>
                </div>

                <div id="push-status" class="hidden">
                  <div class="text-sm text-zinc-600 dark:text-zinc-400">
                    <div id="push-error" class="hidden text-red-600 dark:text-red-400"></div>
                    <div id="push-success" class="hidden text-green-600 dark:text-green-400">
                      Device registered successfully!
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
