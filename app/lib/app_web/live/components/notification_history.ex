defmodule AppWeb.Components.NotificationHistory do
  use AppWeb, :live_component

  alias App.Notifications

  def update(assigns, socket) do
    notifications =
      Notifications.list_notifications(assigns.current_user.id, assigns[:limit] || 20)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:notifications, notifications)}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
      <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
        <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Notification History</h2>
      </div>
      <div class="p-4">
        <%= if Enum.empty?(@notifications) do %>
          <div class="text-center py-8">
            <div class="text-4xl mb-2">📬</div>
            <div class="text-zinc-500 dark:text-zinc-400 mb-2">No notifications sent yet</div>
            <div class="text-sm text-zinc-400 dark:text-zinc-500">
              When fire alerts are triggered, they'll appear here
            </div>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for notification <- @notifications do %>
              <div class="p-3 border border-zinc-200 dark:border-zinc-700 rounded-lg">
                <div class="flex items-start justify-between gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="flex flex-wrap items-center gap-2 mb-1">
                      <span class={[
                        "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium flex-shrink-0",
                        notification_type_class(notification.type)
                      ]}>
                        {notification_type_icon(notification.type)} {format_notification_type(
                          notification.type
                        )}
                      </span>
                      <span class={[
                        "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium flex-shrink-0",
                        notification_status_class(notification.status)
                      ]}>
                        {notification_status_icon(notification.status)} {format_notification_status(
                          notification.status
                        )}
                      </span>
                      <%= if get_delivery_info(notification) do %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400 flex-shrink-0">
                          {get_delivery_info(notification)}
                        </span>
                      <% end %>
                    </div>

                    <div class="mb-2">
                      <h3 class="font-medium text-zinc-900 dark:text-zinc-100 mb-1">
                        {notification.title}
                      </h3>
                      <p class="text-sm text-zinc-600 dark:text-zinc-400">
                        {notification.body}
                      </p>
                    </div>

                    <%= if notification.delivered_at do %>
                      <div class="flex items-center gap-4 text-xs text-zinc-500 dark:text-zinc-400">
                        <span>
                          <strong>Delivered:</strong> {format_datetime(notification.delivered_at)}
                        </span>
                      </div>
                    <% end %>

                    <%= if notification.failure_reason do %>
                      <div class="mt-2 text-xs text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-950/20 p-2 rounded">
                        <strong>Error:</strong> {notification.failure_reason}
                      </div>
                    <% end %>

                    <%= if notification.fire_incident do %>
                      <div class="mt-2 text-xs text-blue-600 dark:text-blue-400">
                        <strong>Related to:</strong>
                        Fire incident at {Float.round(notification.fire_incident.center_latitude, 3)}, {Float.round(
                          notification.fire_incident.center_longitude,
                          3
                        )} ({notification.fire_incident.fire_count} fires)
                      </div>
                    <% end %>
                  </div>

                  <div class="text-xs text-zinc-400 dark:text-zinc-500 flex-shrink-0">
                    <%= if notification.sent_at do %>
                      {time_ago(notification.sent_at)}
                    <% else %>
                      {time_ago(notification.inserted_at)}
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%= if length(@notifications) >= (@limit || 20) do %>
            <div class="mt-4 text-center">
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                Showing recent {length(@notifications)} notifications
              </p>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp notification_type_class("fire_alert"),
    do: "bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400"

  defp notification_type_class("test"),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400"

  defp notification_type_class("system"),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400"

  defp notification_type_class(_),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400"

  defp notification_type_icon("fire_alert"), do: "🔥"
  defp notification_type_icon("test"), do: "🧪"
  defp notification_type_icon("system"), do: "⚙️"
  defp notification_type_icon(_), do: "📧"

  defp format_notification_type("fire_alert"), do: "Fire Alert"
  defp format_notification_type("test"), do: "Test"
  defp format_notification_type("system"), do: "System"
  defp format_notification_type(type), do: String.capitalize(type)

  defp notification_status_class("sent"),
    do: "bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400"

  defp notification_status_class("delivered"),
    do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400"

  defp notification_status_class("failed"),
    do: "bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400"

  defp notification_status_class("pending"),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400"

  defp notification_status_class(_),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400"

  defp notification_status_icon("sent"), do: "✓"
  defp notification_status_icon("delivered"), do: "✅"
  defp notification_status_icon("failed"), do: "✕"
  defp notification_status_icon("pending"), do: "⏳"
  defp notification_status_icon(_), do: "?"

  defp format_notification_status("sent"), do: "Sent"
  defp format_notification_status("delivered"), do: "Delivered"
  defp format_notification_status("failed"), do: "Failed"
  defp format_notification_status("pending"), do: "Pending"
  defp format_notification_status(status), do: String.capitalize(status)

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  defp get_delivery_info(notification) do
    cond do
      # Check if we have device information in the notification data
      notification.data && notification.data["device_name"] && notification.data["device_channel"] ->
        device_name = notification.data["device_name"]

        channel_icon =
          case notification.data["device_channel"] do
            "webhook" -> "🪝"
            "web_push" -> "🌐"
            "email" -> "📧"
            "sms" -> "📱"
            _ -> "📤"
          end

        "#{channel_icon} #{device_name}"

      # Fallback: Check if it's a webhook notification based on data
      notification.data && notification.data["webhook"] ->
        "🪝 Webhook"

      # Check if it's a web push notification (test notifications often go to browser)
      notification.type == "test" && (!notification.data || !notification.data["webhook"]) ->
        "🌐 Web Push"

      # For fire alerts, we could show how many devices it was sent to
      notification.type == "fire_alert" ->
        device_count =
          if notification.data && notification.data["device_count"] do
            notification.data["device_count"]
          else
            "All"
          end

        "📱 #{device_count} devices"

      true ->
        nil
    end
  end

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 ->
        "#{diff}s ago"

      diff < 3600 ->
        minutes = div(diff, 60)
        "#{minutes}m ago"

      diff < 86400 ->
        hours = div(diff, 3600)
        "#{hours}h ago"

      diff < 604_800 ->
        days = div(diff, 86400)
        "#{days}d ago"

      true ->
        format_datetime(datetime)
    end
  end
end
