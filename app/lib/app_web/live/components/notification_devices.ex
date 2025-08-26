defmodule AppWeb.Components.NotificationDevices do
  use AppWeb, :live_component

  alias App.{Notifications, WebPush}

  def handle_event("show_add_form", %{"channel" => channel}, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, true)
     |> assign(:selected_channel, channel)}
  end

  def handle_event("show_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, true)
     |> assign(:selected_channel, nil)}
  end

  def handle_event("select_device_type", %{"type" => channel}, socket) do
    {:noreply, assign(socket, :selected_channel, channel)}
  end

  def handle_event("hide_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, false)
     |> assign(:selected_channel, nil)}
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
    # Send message to parent to handle the async operation
    send(self(), {:send_test_notification, device_id})

    {:noreply, socket}
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
         |> assign(:show_add_modal, false)
         |> assign(:selected_channel, nil)
         |> put_flash(:info, "Device registered successfully!")}

      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {field, {message, _}} -> "#{field} #{message}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Registration failed: #{error_msg}")}
    end
  end

  def handle_event("register_webhook", params, socket) do
    device_attrs = %{
      user_id: socket.assigns.current_user.id,
      name: params["name"],
      channel: "webhook",
      config: %{
        "url" => params["url"]
      }
    }

    case Notifications.create_notification_device(device_attrs) do
      {:ok, _device} ->
        # Refresh the device list after successful registration
        devices = Notifications.list_notification_devices(socket.assigns.current_user.id)

        {:noreply,
         socket
         |> assign(:devices, devices)
         |> assign(:show_add_modal, false)
         |> assign(:selected_channel, nil)
         |> put_flash(:info, "Webhook registered successfully!")}

      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {field, {message, _}} -> "#{field} #{message}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Webhook registration failed: #{error_msg}")}
    end
  end

  def handle_event("test_webhook", _params, socket) do
    # Send message to parent to handle the async operation
    send(self(), {:test_webhook, socket.assigns.current_user.id})

    {:noreply, socket}
  end

  def handle_event("show_webhook_modal", _params, socket) do
    {:noreply, assign(socket, :show_webhook_modal, true)}
  end

  def handle_event("close_webhook_modal", _params, socket) do
    {:noreply, assign(socket, :show_webhook_modal, false)}
  end

  def handle_event("start_edit_device", %{"device_id" => device_id}, socket) do
    case Notifications.get_user_notification_device(socket.assigns.current_user.id, device_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        {:noreply,
         socket
         |> assign(:show_edit_modal, true)
         |> assign(:editing_device, device)}
    end
  end

  def handle_event("cancel_edit_device", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:editing_device, nil)}
  end

  def handle_event(
        "update_device",
        %{"device_id" => device_id, "name" => new_name} = params,
        socket
      ) do
    case Notifications.get_user_notification_device(socket.assigns.current_user.id, device_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        # Build update attributes based on device type
        update_attrs =
          case device.channel do
            "webhook" ->
              new_url = Map.get(params, "url", device.config["url"])

              %{
                name: new_name,
                config: %{"url" => new_url}
              }

            _ ->
              %{name: new_name}
          end

        case Notifications.update_notification_device(device, update_attrs) do
          {:ok, _} ->
            devices = Notifications.list_notification_devices(socket.assigns.current_user.id)

            {:noreply,
             socket
             |> assign(:devices, devices)
             |> assign(:show_edit_modal, false)
             |> assign(:editing_device, nil)
             |> assign(:editing_device_id, nil)
             |> put_flash(:info, "Device updated successfully")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update device")}
        end
    end
  end

  def handle_info(:close_webhook_modal, socket) do
    {:noreply, assign(socket, :show_webhook_modal, false)}
  end

  def update(%{action: :close_modal}, socket) do
    {:ok,
     socket
     |> assign(:show_add_modal, false)
     |> assign(:show_edit_modal, false)
     |> assign(:selected_channel, nil)
     |> assign(:editing_device, nil)}
  end

  def update(assigns, socket) when not is_map_key(assigns, :action) do
    devices = Notifications.list_notification_devices(assigns.current_user.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:devices, devices)
     |> assign(:show_add_modal, false)
     |> assign(:selected_channel, nil)
     |> assign(:show_webhook_modal, false)
     |> assign(:show_edit_modal, false)
     |> assign(:editing_device, nil)
     |> assign(:editing_device_id, nil)}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
      <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Notification Devices</h2>
          <button
            phx-click="show_add_form"
            phx-target={@myself}
            class="inline-flex items-center px-3 py-1.5 text-sm font-medium text-blue-600 hover:text-blue-700 border border-blue-200 dark:border-blue-700 rounded-md hover:bg-blue-50 dark:hover:bg-blue-950/20 transition-colors"
          >
            + Add
          </button>
        </div>
      </div>
      <div class="overflow-hidden">
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
          <div class="max-h-96 overflow-y-auto">
            <div class="p-4 space-y-3">
              <%= for device <- @devices do %>
                <div class="p-3 border border-zinc-200 dark:border-zinc-700 rounded-lg">
                  <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                    <div class="flex-1 min-w-0">
                      <div class="flex flex-wrap items-center gap-2 mb-1">
                        <span class="font-medium text-zinc-900 dark:text-zinc-100 truncate">
                          {device.name}
                        </span>
                        <button
                          phx-click="start_edit_device"
                          phx-value-device_id={device.id}
                          phx-target={@myself}
                          class="p-1 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 transition-colors"
                          title="Edit device"
                        >
                          ✏️
                        </button>
                        <%= if device.channel == "web_push" do %>
                          <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400 flex-shrink-0">
                            Web Push
                          </span>
                        <% end %>
                        <%= if device.channel == "webhook" do %>
                          <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-purple-100 text-purple-800 dark:bg-purple-900/20 dark:text-purple-400 flex-shrink-0">
                            Webhook
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
                        disabled={!device.active}
                        class="flex-1 sm:flex-none px-3 py-1.5 text-xs font-medium text-blue-600 hover:text-blue-700 disabled:opacity-50 disabled:cursor-not-allowed border border-blue-200 dark:border-blue-700 rounded hover:bg-blue-50 dark:hover:bg-blue-950/20 transition-colors"
                      >
                        Test
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
          </div>
        <% end %>

        <%= if @show_add_modal do %>
          <.live_component
            module={AppWeb.Components.Modal}
            id="add-device-modal"
            parent_component={__MODULE__}
            parent_id="notification-devices"
            title={
              cond do
                @selected_channel == "webhook" -> "Register Webhook"
                @selected_channel == "web_push" -> "Register Web Push Device"
                true -> "Add Device"
              end
            }
            max_width="max-w-lg"
          >
            <%= if @selected_channel == nil do %>
              <div class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-3">
                    Choose Device Type
                  </label>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <button
                      type="button"
                      phx-click="select_device_type"
                      phx-value-type="web_push"
                      phx-target={@myself}
                      class="group relative p-4 bg-white dark:bg-zinc-950 border border-zinc-300 dark:border-zinc-700 rounded-lg hover:border-blue-400 dark:hover:border-blue-500 hover:bg-blue-50 dark:hover:bg-blue-950/10 transition-all duration-200 text-left"
                    >
                      <div class="flex items-center">
                        <div class="text-2xl mr-3">🌐</div>
                        <div>
                          <h4 class="font-medium text-zinc-900 dark:text-zinc-100 group-hover:text-blue-700 dark:group-hover:text-blue-400">
                            Web Push
                          </h4>
                          <p class="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
                            Browser notifications
                          </p>
                        </div>
                      </div>
                    </button>
                    <button
                      type="button"
                      phx-click="select_device_type"
                      phx-value-type="webhook"
                      phx-target={@myself}
                      class="group relative p-4 bg-white dark:bg-zinc-950 border border-zinc-300 dark:border-zinc-700 rounded-lg hover:border-purple-400 dark:hover:border-purple-500 hover:bg-purple-50 dark:hover:bg-purple-950/10 transition-all duration-200 text-left"
                    >
                      <div class="flex items-center">
                        <div class="text-2xl mr-3">🪝</div>
                        <div>
                          <h4 class="font-medium text-zinc-900 dark:text-zinc-100 group-hover:text-purple-700 dark:group-hover:text-purple-400">
                            Webhook
                          </h4>
                          <p class="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
                            HTTP API endpoint
                          </p>
                        </div>
                      </div>
                    </button>
                  </div>
                </div>
              </div>
            <% else %>
              <%= if @selected_channel == "webhook" do %>
                <form
                  id="webhook-form"
                  phx-submit="register_webhook"
                  phx-target={@myself}
                  class="space-y-4"
                >
                  <div>
                    <label
                      for="webhook-name"
                      class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2"
                    >
                      Webhook Name
                    </label>
                    <input
                      type="text"
                      id="webhook-name"
                      name="name"
                      required
                      placeholder="My API, Slack Integration, etc."
                      class="w-full px-3 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-purple-400 focus:ring-1 focus:ring-purple-400 text-sm"
                    />
                  </div>

                  <div>
                    <label
                      for="webhook-url"
                      class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2"
                    >
                      Webhook URL
                    </label>
                    <input
                      type="url"
                      id="webhook-url"
                      name="url"
                      required
                      placeholder="https://api.example.com/webhooks/fire-alerts"
                      class="w-full px-3 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-purple-400 focus:ring-1 focus:ring-purple-400 text-sm"
                    />
                    <p class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
                      This URL will receive HTTP POST requests with fire alert notifications.
                    </p>
                  </div>

                  <div class="flex gap-2">
                    <button
                      type="submit"
                      class="flex-1 inline-flex items-center justify-center px-4 py-2.5 bg-purple-600 text-white text-sm font-medium rounded-md hover:bg-purple-700 transition-colors focus:outline-none focus:ring-2 focus:ring-purple-500 focus:ring-offset-2"
                    >
                      Register Webhook
                    </button>
                  </div>

                  <div class="text-center text-sm text-zinc-500 dark:text-zinc-400">
                    Register the webhook first, then use the Test button to verify it works
                  </div>

                  <div class="text-center">
                    <button
                      type="button"
                      phx-click="show_webhook_modal"
                      phx-target={@myself}
                      class="text-xs text-purple-600 hover:text-purple-700 underline"
                    >
                      How to verify webhook signatures
                    </button>
                  </div>
                </form>
              <% else %>
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
              <% end %>
            <% end %>
          </.live_component>
        <% end %>

        <%= if @show_edit_modal && @editing_device do %>
          <.live_component
            module={AppWeb.Components.Modal}
            id="edit-device-modal"
            parent_component={__MODULE__}
            parent_id="notification-devices"
            title="Edit Device"
            max_width="max-w-lg"
          >
            <form
              phx-submit="update_device"
              phx-target={@myself}
              class="space-y-4"
            >
              <input type="hidden" name="device_id" value={@editing_device.id} />

              <div>
                <label
                  for="edit-device-name"
                  class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2"
                >
                  Device Name
                </label>
                <input
                  type="text"
                  id="edit-device-name"
                  name="name"
                  value={@editing_device.name}
                  placeholder="Device name"
                  class="w-full px-3 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-blue-400 focus:ring-1 focus:ring-blue-400 text-sm"
                  required
                  autofocus
                />
              </div>

              <%= if @editing_device.channel == "webhook" do %>
                <div>
                  <label
                    for="edit-webhook-url"
                    class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2"
                  >
                    Webhook URL
                  </label>
                  <input
                    type="url"
                    id="edit-webhook-url"
                    name="url"
                    value={@editing_device.config["url"]}
                    placeholder="https://api.example.com/webhooks/fire-alerts"
                    class="w-full px-3 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-purple-400 focus:ring-1 focus:ring-purple-400 text-sm"
                    required
                  />
                  <p class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
                    This URL will receive HTTP POST requests with fire alert notifications.
                  </p>
                </div>
              <% end %>

              <div class="flex gap-3 pt-4">
                <button
                  type="submit"
                  class="flex-1 inline-flex items-center justify-center px-4 py-2.5 bg-green-600 text-white text-sm font-medium rounded-md hover:bg-green-700 transition-colors focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2"
                >
                  Save Changes
                </button>
                <button
                  type="button"
                  phx-click="cancel_edit_device"
                  phx-target={@myself}
                  class="flex-1 inline-flex items-center justify-center px-4 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-700 dark:text-zinc-200 text-sm font-medium rounded-md hover:bg-zinc-50 dark:hover:bg-zinc-800 transition-colors focus:outline-none focus:ring-2 focus:ring-zinc-500 focus:ring-offset-2"
                >
                  Cancel
                </button>
              </div>
            </form>
          </.live_component>
        <% end %>

        <%= if @show_webhook_modal do %>
          <.live_component
            module={AppWeb.Components.WebhookVerificationModal}
            id="webhook-verification-modal"
          />
        <% end %>
      </div>
    </div>
    """
  end
end
