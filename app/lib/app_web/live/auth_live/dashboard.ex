defmodule AppWeb.AuthLive.Dashboard do
  use AppWeb, :live_view
  alias App.{Location, Notifications}

  def mount(_params, _session, socket) do
    # Subscribe to notifications for this user
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "notifications:#{socket.assigns.current_user.id}")
    end

    # current_user is set by the on_mount hook
    locations = Location.list_for_user(socket.assigns.current_user.id)
    fires = App.Fire.fires_near_locations(locations, quality: :all, status: :all)
    incidents = App.FireIncident.incidents_from_fires(fires)

    # Separate incidents by status
    active_incidents = Enum.filter(incidents, &(&1.status == "active"))
    ended_incidents = Enum.filter(incidents, &(&1.status == "ended"))

    socket =
      socket
      |> assign(:locations, locations)
      |> assign(:fires, fires)
      |> assign(:incidents, incidents)
      |> assign(:active_incidents, active_incidents)
      |> assign(:ended_incidents, ended_incidents)
      |> push_data_to_map(locations, fires)

    {:ok, socket}
  end

  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> redirect(external: "/session/logout")}
  end

  def handle_event("trigger_location_modal", _params, socket) do
    # Send message to locations widget to show the modal
    send_update(AppWeb.Components.LocationsWidget,
      id: "locations-widget",
      current_user: socket.assigns.current_user,
      action: :show_modal
    )

    {:noreply, socket}
  end

  def handle_event("center_map_on_incident", params, socket) do
    incident_id = params["incident-id"]

    # Find the incident from the already-loaded incidents in socket assigns
    incident = Enum.find(socket.assigns.incidents, fn i -> i.id == incident_id end)

    case incident do
      nil ->
        # Fallback if incident not found
        lat = parse_float(params["lat"])
        lng = parse_float(params["lng"])

        {:noreply,
         socket
         |> push_event("center_map", %{
           latitude: lat,
           longitude: lng,
           zoom: 14,
           incident_id: incident_id,
           type: "incident"
         })}

      incident ->
        # Check if incident has bounds data
        if incident.min_latitude && incident.max_latitude && incident.min_longitude &&
             incident.max_longitude do
          # Add 10% padding to bounds
          lat_range = incident.max_latitude - incident.min_latitude
          lng_range = incident.max_longitude - incident.min_longitude
          padding_lat = lat_range * 0.1
          padding_lng = lng_range * 0.1

          bounds = %{
            min_lat: incident.min_latitude - padding_lat,
            max_lat: incident.max_latitude + padding_lat,
            min_lng: incident.min_longitude - padding_lng,
            max_lng: incident.max_longitude + padding_lng
          }

          {:noreply,
           socket
           |> push_event("center_map", %{
             latitude: incident.center_latitude,
             longitude: incident.center_longitude,
             incident_id: incident_id,
             type: "incident",
             bounds: bounds
           })}
        else
          # Fallback to center point only
          {:noreply,
           socket
           |> push_event("center_map", %{
             latitude: incident.center_latitude,
             longitude: incident.center_longitude,
             zoom: 14,
             incident_id: incident_id,
             type: "incident"
           })}
        end
    end
  end

  def handle_event("center_map_on_location", params, socket) do
    lat = parse_float(params["lat"])
    lng = parse_float(params["lng"])
    radius = String.to_integer(params["radius"])
    location_id = params["location-id"]

    # Calculate appropriate zoom level based on radius
    zoom = calculate_zoom_for_radius(radius)

    # Push event to center map on the location
    {:noreply,
     socket
     |> push_event("center_map", %{
       latitude: lat,
       longitude: lng,
       zoom: zoom,
       location_id: location_id,
       radius: radius,
       type: "location"
     })}
  end

  def handle_event("map_pick_coords", %{"latitude" => lat, "longitude" => lng}, socket) do
    # Re-open the locations modal with prefilled coordinates
    send_update(AppWeb.Components.LocationsWidget,
      id: "locations-widget",
      current_user: socket.assigns.current_user,
      action: :prefill_coords,
      latitude: lat,
      longitude: lng
    )

    {:noreply, socket}
  end

  def handle_info({:send_test_notification, device_id}, socket) do
    try do
      case Notifications.get_user_notification_device(socket.assigns.current_user.id, device_id) do
        nil ->
          {:noreply, put_flash(socket, :error, "Device not found")}

        device ->
          # Create a test notification with device context
          test_notification_attrs = %{
            user_id: socket.assigns.current_user.id,
            fire_incident_id: nil,
            title: "Test Notification",
            body: "This is a test notification to verify your device is working correctly.",
            type: "test",
            data: %{
              "test" => true,
              "device_name" => device.name,
              "device_channel" => device.channel,
              "webhook" => device.channel == "webhook"
            }
          }

          # Use the test notification function that creates only device notifications
          case Notifications.send_test_notification_to_device(device.id, test_notification_attrs) do
            {:ok, %{sent: sent_count, failed: failed_count}} ->
              cond do
                sent_count > 0 and failed_count == 0 ->
                  {:noreply,
                   put_flash(socket, :info, "Test notification sent to #{device.name}!")}

                sent_count > 0 and failed_count > 0 ->
                  {:noreply,
                   put_flash(
                     socket,
                     :warning,
                     "Test notification partially sent to #{device.name} (#{failed_count} failures)"
                   )}

                sent_count == 0 and failed_count > 0 ->
                  {:noreply,
                   put_flash(socket, :error, "Failed to send test notification to #{device.name}")}
              end

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to send test notification: #{reason}")}
          end
      end
    rescue
      error ->
        # Log the error for debugging
        require Logger
        Logger.error("Error in send_test_notification: #{inspect(error)}")

        {:noreply,
         put_flash(
           socket,
           :error,
           "An unexpected error occurred while sending the test notification"
         )}
    end
  end

  def handle_info({:notification_created, _notification}, socket) do
    # Update the NotificationHistory component with the new notification
    # We'll pass the notification data to trigger a re-render
    send_update(AppWeb.Components.NotificationHistory,
      id: "notification-history",
      current_user: socket.assigns.current_user,
      limit: 10
    )

    {:noreply, socket}
  end

  def handle_info({:location_updated}, socket) do
    # Reload locations and fires when a location is updated
    {:noreply, reload_locations_and_fires(socket)}
  end

  defp reload_locations_and_fires(socket) do
    locations = Location.list_for_user(socket.assigns.current_user.id)
    fires = App.Fire.fires_near_locations(locations, quality: :all, status: :all)
    incidents = App.FireIncident.incidents_from_fires(fires)

    # Separate incidents by status
    active_incidents = Enum.filter(incidents, &(&1.status == "active"))
    ended_incidents = Enum.filter(incidents, &(&1.status == "ended"))

    socket
    |> assign(:locations, locations)
    |> assign(:fires, fires)
    |> assign(:incidents, incidents)
    |> assign(:active_incidents, active_incidents)
    |> assign(:ended_incidents, ended_incidents)
    |> push_data_to_map(locations, fires)
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {float, _} -> float
      :error -> String.to_integer(str) * 1.0
    end
  end

  defp calculate_zoom_for_radius(radius_meters) do
    # Calculate appropriate zoom level to show the location's monitoring area
    cond do
      # > 100km
      radius_meters > 100_000 -> 7
      # > 50km
      radius_meters > 50_000 -> 8
      # > 20km
      radius_meters > 20_000 -> 10
      # > 10km
      radius_meters > 10_000 -> 11
      # > 5km
      radius_meters > 5_000 -> 12
      # > 2km
      radius_meters > 2_000 -> 13
      # <= 2km
      true -> 14
    end
  end

  defp push_data_to_map(socket, locations, fires) do
    # Use MessagePack for compact fire data transmission
    compact_fires = App.Fire.to_compact_msgpack(fires)

    case Msgpax.pack(compact_fires) do
      {:ok, msgpack_iodata} ->
        # Convert iodata to binary, then encode as base64 for transmission over Phoenix channels
        msgpack_binary = IO.iodata_to_binary(msgpack_iodata)
        encoded_fires = Base.encode64(msgpack_binary)

        push_event(socket, "update_map_data", %{
          locations: locations,
          fires_msgpack: encoded_fires,
          fires_count: length(fires)
        })

      {:error, reason} ->
        # Fallback to regular JSON if MessagePack fails
        IO.puts("MessagePack encoding failed: #{inspect(reason)}")
        push_event(socket, "update_map_data", %{locations: locations, fires: fires})
    end
  end

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 ->
        "#{diff_seconds}s ago"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes}m ago"

      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        "#{hours}h ago"

      true ->
        days = div(diff_seconds, 86400)
        "#{days}d ago"
    end
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Locations Overview -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <!-- Locations Counter Widget -->
        <div class={"bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 #{if Enum.empty?(@locations), do: "ring-orange-300 dark:ring-orange-700 bg-orange-50 dark:bg-orange-950", else: "ring-zinc-200 dark:ring-zinc-800"}"}>
          <div class="p-6 text-center">
            <%= if Enum.empty?(@locations) do %>
              <div class="text-4xl font-bold text-orange-600 dark:text-orange-400 mb-2">
                📍
              </div>
              <div class="text-lg font-medium text-orange-900 dark:text-orange-100 mb-1">
                No Locations Yet
              </div>
              <div class="text-sm text-orange-700 dark:text-orange-300">
                Add your first location to start monitoring
              </div>
            <% else %>
              <div class="text-4xl font-bold text-blue-600 dark:text-blue-400 mb-2">
                {length(@locations)}
              </div>
              <div class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-1">
                Monitored Locations
              </div>
              <div class="text-sm text-zinc-500 dark:text-zinc-400">
                Areas being watched for fires
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Add Location Widget -->
        <div class={"bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 #{if Enum.empty?(@locations), do: "ring-blue-300 dark:ring-blue-700 bg-blue-50 dark:bg-blue-950", else: "ring-zinc-200 dark:ring-zinc-800"}"}>
          <div class="p-6 text-center">
            <button
              phx-click="trigger_location_modal"
              class={"w-full h-full flex flex-col items-center justify-center transition-colors group #{if Enum.empty?(@locations), do: "text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300", else: "text-zinc-600 dark:text-zinc-400 hover:text-blue-600 dark:hover:text-blue-400"}"}
            >
              <%= if Enum.empty?(@locations) do %>
                <div class="text-4xl font-bold mb-2 text-blue-600 dark:text-blue-400 group-hover:text-blue-700 dark:group-hover:text-blue-300 animate-pulse">
                  ➕
                </div>
                <div class="text-lg font-medium text-blue-900 dark:text-blue-100 mb-1">
                  Add Your First Location
                </div>
                <div class="text-sm text-blue-700 dark:text-blue-300 font-medium">
                  Start monitoring for fires!
                </div>
              <% else %>
                <div class="text-4xl font-bold mb-2 group-hover:text-blue-600 dark:group-hover:text-blue-400">
                  +
                </div>
                <div class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-1">
                  Add Location
                </div>
                <div class="text-sm text-zinc-500 dark:text-zinc-400">
                  Monitor a new area
                </div>
              <% end %>
            </button>
          </div>
        </div>
        
    <!-- Fire Detection Status Widget -->
        <div class={"bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800 #{if Enum.empty?(@locations), do: "opacity-50"}"}>
          <div class="p-6 text-center">
            <%= if Enum.empty?(@locations) do %>
              <div class="text-4xl font-bold text-zinc-400 dark:text-zinc-600 mb-2">
                🚫
              </div>
              <div class="text-lg font-medium text-zinc-500 dark:text-zinc-500 mb-1">
                No Monitoring
              </div>
              <div class="text-sm text-zinc-400 dark:text-zinc-600">
                Add locations to detect fires
              </div>
            <% else %>
              <%= if length(@active_incidents) > 0 do %>
                <div class="text-4xl font-bold text-red-600 dark:text-red-400 mb-2">
                  🔥
                </div>
                <div class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-1">
                  Fires Detected
                </div>
                <div class="text-sm text-red-600 dark:text-red-400">
                  {length(@active_incidents)} active incident{if length(@active_incidents) != 1,
                    do: "s"}
                </div>
              <% else %>
                <div class="text-4xl font-bold text-emerald-600 dark:text-emerald-400 mb-2">
                  ✅
                </div>
                <div class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-1">
                  All Clear
                </div>
                <div class="text-sm text-emerald-600 dark:text-emerald-400">
                  No active fire incidents
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Map and Locations Management -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Interactive Map -->
        <div class={"lg:col-span-2 bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800 #{if Enum.empty?(@locations), do: "opacity-50"}"}>
          <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
            <h2 class={"text-lg font-semibold #{if Enum.empty?(@locations), do: "text-zinc-500 dark:text-zinc-500", else: "text-zinc-900 dark:text-zinc-100"}"}>
              Fire Monitoring Map
            </h2>
          </div>
          <div class="p-4 relative">
            <%= if Enum.empty?(@locations) do %>
              <div class="absolute inset-0 bg-zinc-100 dark:bg-zinc-800 rounded-md flex items-center justify-center z-10">
                <div class="text-center">
                  <div class="text-3xl mb-2">🗺️</div>
                  <div class="text-zinc-600 dark:text-zinc-400 font-medium mb-1">Map Disabled</div>
                  <div class="text-sm text-zinc-500 dark:text-zinc-500">
                    Add a location to activate monitoring
                  </div>
                </div>
              </div>
            <% end %>
            <div
              id="locations-map"
              phx-hook="Map"
              phx-update="ignore"
              class="h-[400px] w-full rounded-md"
            >
            </div>
            <!-- Map Legend -->
            <div class="mt-3 text-xs text-zinc-500 dark:text-zinc-400 flex flex-wrap gap-x-4 gap-y-1">
              <div class="flex items-center gap-1">
                <span class="inline-block w-3 h-3 bg-blue-600 rounded-full"></span>
                <span>Monitored Locations</span>
              </div>
              <div class="flex items-center gap-1">
                <span class="inline-block w-3 h-3 bg-orange-500 rounded-full"></span>
                <span>Recent Fires (&lt;24h)</span>
              </div>
              <div class="flex items-center gap-1">
                <span class="inline-block w-3 h-3 bg-gray-400 rounded-full"></span>
                <span>Older Fires (&gt;24h)</span>
              </div>
              <div class="flex items-center gap-1">
                <span class="inline-block w-5 h-5 bg-red-600 rounded-full flex items-center justify-center text-white text-xs font-bold">
                  🔥
                </span>
                <span>Fire Clusters</span>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Locations Widget -->
        <.live_component
          module={AppWeb.Components.LocationsWidget}
          id="locations-widget"
          current_user={@current_user}
        />
      </div>
      
    <!-- Statistics Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <!-- Active Incidents Counter -->
        <div class={"bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800 #{if Enum.empty?(@locations), do: "opacity-50"}"}>
          <div class="p-6 text-center">
            <%= if Enum.empty?(@locations) do %>
              <div class="text-4xl font-bold text-zinc-400 dark:text-zinc-600 mb-2">
                -
              </div>
              <div class="text-lg font-medium text-zinc-500 dark:text-zinc-500 mb-1">
                Active Fire Incidents
              </div>
              <div class="text-sm text-zinc-400 dark:text-zinc-600">
                Add locations to monitor incidents
              </div>
            <% else %>
              <div class="text-4xl font-bold text-red-600 dark:text-red-400 mb-2">
                {length(@active_incidents)}
              </div>
              <div class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-1">
                Active Fire Incidents
              </div>
              <div class="text-sm text-zinc-500 dark:text-zinc-400">
                Fire activity detected in the last 24 hours
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Ended Incidents Counter -->
        <div class={"bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800 #{if Enum.empty?(@locations), do: "opacity-50"}"}>
          <div class="p-6 text-center">
            <%= if Enum.empty?(@locations) do %>
              <div class="text-4xl font-bold text-zinc-400 dark:text-zinc-600 mb-2">
                -
              </div>
              <div class="text-lg font-medium text-zinc-500 dark:text-zinc-500 mb-1">
                Ended Fire Incidents
              </div>
              <div class="text-sm text-zinc-400 dark:text-zinc-600">
                Add locations to monitor incidents
              </div>
            <% else %>
              <div class="text-4xl font-bold text-zinc-600 dark:text-zinc-400 mb-2">
                {length(@ended_incidents)}
              </div>
              <div class="text-lg font-medium text-zinc-900 dark:text-zinc-100 mb-1">
                Ended Fire Incidents
              </div>
              <div class="text-sm text-zinc-500 dark:text-zinc-400">
                No fire activity in the last 24 hours
              </div>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Incident Tables -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Active Incidents Table -->
        <div class={"bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800 #{if Enum.empty?(@locations), do: "opacity-50"}"}>
          <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
            <h2 class={"text-lg font-semibold #{if Enum.empty?(@locations), do: "text-zinc-500 dark:text-zinc-500", else: "text-zinc-900 dark:text-zinc-100"}"}>
              Active Fire Incidents
            </h2>
          </div>
          <div class="overflow-hidden">
            <%= if Enum.empty?(@active_incidents) do %>
              <div class="text-center py-8 text-zinc-500">
                <div class="mb-2">🔥</div>
                <p>No active fire incidents.</p>
                <p class="text-sm">This is good news!</p>
              </div>
            <% else %>
              <div class="max-h-96 overflow-y-auto">
                <table class="min-w-full divide-y divide-zinc-200 dark:divide-zinc-800">
                  <thead class="bg-zinc-50 dark:bg-zinc-900 sticky top-0">
                    <tr>
                      <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
                        Location
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
                        Fires
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
                        Intensity
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
                        Last Activity
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-zinc-200 dark:divide-zinc-800">
                    <%= for incident <- @active_incidents do %>
                      <tr
                        class="hover:bg-zinc-50 dark:hover:bg-zinc-900 cursor-pointer"
                        phx-click="center_map_on_incident"
                        phx-value-lat={incident.center_latitude}
                        phx-value-lng={incident.center_longitude}
                        phx-value-incident-id={incident.id}
                      >
                        <td class="px-4 py-4 whitespace-nowrap">
                          <div class="text-sm font-medium text-zinc-900 dark:text-zinc-100">
                            {Float.round(incident.center_latitude, 3)}, {Float.round(
                              incident.center_longitude,
                              3
                            )}
                          </div>
                          <div class="text-xs text-zinc-500 dark:text-zinc-400 font-mono">
                            {String.slice(incident.id, 0, 8)}...
                          </div>
                        </td>
                        <td class="px-4 py-4 whitespace-nowrap">
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400">
                            {incident.fire_count}
                          </span>
                        </td>
                        <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-900 dark:text-zinc-100">
                          <%= if incident.max_frp do %>
                            {Float.round(incident.max_frp, 1)} MW
                          <% else %>
                            -
                          <% end %>
                        </td>
                        <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500 dark:text-zinc-400">
                          {time_ago(incident.last_detected_at)}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Ended Incidents Table -->
        <div class={"bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800 #{if Enum.empty?(@locations), do: "opacity-50"}"}>
          <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
            <h2 class={"text-lg font-semibold #{if Enum.empty?(@locations), do: "text-zinc-500 dark:text-zinc-500", else: "text-zinc-900 dark:text-zinc-100"}"}>
              Recently Ended Incidents
            </h2>
          </div>
          <div class="overflow-hidden">
            <%= if Enum.empty?(@ended_incidents) do %>
              <div class="text-center py-8 text-zinc-500">
                <div class="mb-2">✅</div>
                <p>No recently ended incidents.</p>
                <p class="text-sm">All clear!</p>
              </div>
            <% else %>
              <div class="max-h-96 overflow-y-auto">
                <table class="min-w-full divide-y divide-zinc-200 dark:divide-zinc-800">
                  <thead class="bg-zinc-50 dark:bg-zinc-900 sticky top-0">
                    <tr>
                      <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
                        Location
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
                        Fires
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
                        Duration
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">
                        Ended
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-zinc-200 dark:divide-zinc-800">
                    <%= for incident <- @ended_incidents do %>
                      <tr
                        class="hover:bg-zinc-50 dark:hover:bg-zinc-900 cursor-pointer"
                        phx-click="center_map_on_incident"
                        phx-value-lat={incident.center_latitude}
                        phx-value-lng={incident.center_longitude}
                        phx-value-incident-id={incident.id}
                      >
                        <td class="px-4 py-4 whitespace-nowrap">
                          <div class="text-sm font-medium text-zinc-900 dark:text-zinc-100">
                            {Float.round(incident.center_latitude, 3)}, {Float.round(
                              incident.center_longitude,
                              3
                            )}
                          </div>
                          <div class="text-xs text-zinc-500 dark:text-zinc-400 font-mono">
                            {String.slice(incident.id, 0, 8)}...
                          </div>
                        </td>
                        <td class="px-4 py-4 whitespace-nowrap">
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-zinc-100 text-zinc-800 dark:bg-zinc-700 dark:text-zinc-300">
                            {incident.fire_count}
                          </span>
                        </td>
                        <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-900 dark:text-zinc-100">
                          <%= if incident.ended_at && incident.first_detected_at do %>
                            <% duration_hours =
                              DateTime.diff(incident.ended_at, incident.first_detected_at, :second) /
                                3600 %>
                            <%= cond do %>
                              <% duration_hours < 24 -> %>
                                {Float.round(duration_hours, 1)}h
                              <% true -> %>
                                {Float.round(duration_hours / 24, 1)}d
                            <% end %>
                          <% else %>
                            -
                          <% end %>
                        </td>
                        <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500 dark:text-zinc-400">
                          <%= if incident.ended_at do %>
                            {time_ago(incident.ended_at)}
                          <% else %>
                            -
                          <% end %>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Notification Devices and Notification History -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Notification Devices Widget -->
        <.live_component
          module={AppWeb.Components.NotificationDevices}
          id="notification-devices"
          current_user={@current_user}
        />
        
    <!-- Notification History -->
        <.live_component
          module={AppWeb.Components.NotificationHistory}
          id="notification-history"
          current_user={@current_user}
          limit={5}
        />
      </div>
      
    <!-- Account Settings -->
      <div class="grid grid-cols-1 gap-6">
        <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
          <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
            <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Account</h2>
          </div>
          <div class="p-4 space-y-2 text-sm">
            <div class="flex items-center justify-between">
              <span class="text-zinc-500">Email</span>
              <span class="font-medium text-zinc-900 dark:text-zinc-100 truncate">
                {@current_user.email}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-zinc-500">Member since</span>
              <span class="font-medium text-zinc-900 dark:text-zinc-100">
                {Calendar.strftime(@current_user.inserted_at, "%B %d, %Y")}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
