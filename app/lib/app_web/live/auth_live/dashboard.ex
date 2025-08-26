defmodule AppWeb.AuthLive.Dashboard do
  use AppWeb, :live_view
  alias App.{Location, Notifications, Notification, NotificationDevice}

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
      |> assign(:show_form, false)
      |> assign(:form, to_form(%{}))
      |> assign(:editing_location_id, nil)
      |> assign(:updating_location_id, nil)
      |> assign(:updating_location_data, nil)
      |> assign(:creating_location, false)
      |> assign(:deleting_location_id, nil)
      |> push_data_to_map(locations, fires)

    {:ok, socket}
  end

  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> redirect(external: "/session/logout")}
  end

  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("hide_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> push_event("clear_radius_preview", %{})}
  end

  def handle_event("create_location", params, socket) do
    # Set loading state and send immediate response
    socket_with_loading = assign(socket, :creating_location, true)

    # Send the loading state immediately
    send(self(), {:complete_create, params})

    {:noreply, socket_with_loading}
  end

  def handle_event("delete_location", %{"id" => id}, socket) do
    # Set loading state and send immediate response
    socket_with_loading = assign(socket, :deleting_location_id, id)

    # Send the loading state immediately
    send(self(), {:complete_delete, id})

    {:noreply, socket_with_loading}
  end

  def handle_event("start_edit_location", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_location_id, id)}
  end

  def handle_event("cancel_edit_location", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_location_id, nil)
     |> push_event("clear_radius_preview", %{})}
  end

  def handle_event("update_location", params, socket) do
    id = params["_id"]
    location = App.Repo.get(Location, id)

    # Parse the radius to store the submitted values
    radius_meters =
      cond do
        is_binary(params["radius"]) and params["radius"] != "" ->
          String.to_integer(params["radius"])

        is_binary(params["radius_km"]) and params["radius_km"] != "" ->
          params["radius_km"] |> parse_float() |> Kernel.*(1000.0) |> Float.round() |> trunc()

        true ->
          location.radius
      end

    # Store the submitted form data for display during loading
    updating_data = %{
      name: params["name"],
      latitude: parse_float(params["latitude"]),
      longitude: parse_float(params["longitude"]),
      radius: radius_meters
    }

    # Set loading state and send immediate response
    socket_with_loading =
      socket
      |> assign(:updating_location_id, id)
      |> assign(:updating_location_data, updating_data)

    # Send the loading state immediately
    send(self(), {:complete_update, params})

    {:noreply, socket_with_loading}
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

  def handle_info({:complete_create, params}, socket) do
    radius_meters =
      cond do
        is_binary(params["radius"]) and params["radius"] != "" ->
          String.to_integer(params["radius"])

        is_binary(params["radius_km"]) and params["radius_km"] != "" ->
          params["radius_km"] |> parse_float() |> Kernel.*(1000.0) |> Float.round() |> trunc()

        true ->
          50_000
      end

    attrs = %{
      "name" => params["name"],
      "latitude" => parse_float(params["latitude"]),
      "longitude" => parse_float(params["longitude"]),
      "radius" => radius_meters
    }

    case Location.create_location(socket.assigns.current_user, attrs) do
      {:ok, _location} ->
        {:noreply,
         socket
         |> reload_locations_and_fires()
         |> assign(:show_form, false)
         |> assign(:creating_location, false)
         |> put_flash(:info, "Location added successfully!")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:creating_location, false)
         |> put_flash(:error, "Error creating location")}
    end
  end

  def handle_info({:complete_delete, id}, socket) do
    location = App.Repo.get(Location, id)

    case Location.delete_location(location) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_locations_and_fires()
         |> assign(:deleting_location_id, nil)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:deleting_location_id, nil)
         |> put_flash(:error, "Error deleting location")}
    end
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

          case Notifications.create_notification(test_notification_attrs) do
            {:ok, notification} ->
              # Route to the appropriate notification sender based on device channel
              result =
                case device.channel do
                  "web_push" ->
                    App.WebPush.send_notification(notification, device)

                  "webhook" ->
                    App.Webhook.send_notification(notification, device)

                  _ ->
                    {:error, "Unsupported notification channel: #{device.channel}"}
                end

              case result do
                :ok ->
                  # Update the device's last_used_at timestamp
                  NotificationDevice.update_last_used(device)
                  # Mark the notification as sent
                  Notification.mark_as_sent(notification)

                  {:noreply,
                   put_flash(socket, :info, "Test notification sent to #{device.name}!")}

                {:error, reason} ->
                  # Mark the notification as failed
                  Notification.mark_as_failed(notification, reason)

                  {:noreply,
                   put_flash(socket, :error, "Failed to send test notification: #{reason}")}
              end

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to create test notification")}
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

  def handle_info({:complete_update, params}, socket) do
    id = params["_id"]
    location = App.Repo.get(Location, id)

    radius_meters =
      cond do
        is_binary(params["radius"]) and params["radius"] != "" ->
          String.to_integer(params["radius"])

        is_binary(params["radius_km"]) and params["radius_km"] != "" ->
          params["radius_km"] |> parse_float() |> Kernel.*(1000.0) |> Float.round() |> trunc()

        true ->
          location.radius
      end

    attrs = %{
      "name" => params["name"],
      "latitude" => parse_float(params["latitude"]),
      "longitude" => parse_float(params["longitude"]),
      "radius" => radius_meters
    }

    case Location.update_location(location, attrs) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> reload_locations_and_fires()
         |> assign(:editing_location_id, nil)
         |> assign(:updating_location_id, nil)
         |> assign(:updating_location_data, nil)
         |> push_event("clear_radius_preview", %{})
         |> put_flash(:info, "Location updated successfully!")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:updating_location_id, nil)
         |> assign(:updating_location_data, nil)
         |> put_flash(:error, "Error updating location")}
    end
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

  defp get_display_location(location, updating_location_id, updating_location_data) do
    if updating_location_data && to_string(location.id) == to_string(updating_location_id) do
      # Use the updating data during loading state
      %{
        name: updating_location_data.name,
        latitude: updating_location_data.latitude,
        longitude: updating_location_data.longitude,
        radius: updating_location_data.radius
      }
    else
      # Use the actual location data
      location
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
              phx-click="show_form"
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
        <div class={"lg:col-span-2 bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800 #{if Enum.empty?(@locations) and not @show_form, do: "opacity-50"}"}>
          <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
            <h2 class={"text-lg font-semibold #{if Enum.empty?(@locations) and not @show_form, do: "text-zinc-500 dark:text-zinc-500", else: "text-zinc-900 dark:text-zinc-100"}"}>
              Fire Monitoring Map
            </h2>
          </div>
          <div class="p-4 relative">
            <%= if Enum.empty?(@locations) and not @show_form do %>
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
              data-editing-id={@editing_location_id}
              class="h-[400px] w-full rounded-md"
              style={
                if @show_form or @editing_location_id,
                  do: "cursor: crosshair !important;",
                  else: "cursor: default !important;"
              }
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
        
    <!-- Locations List -->
        <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
          <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
            <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Your Locations</h2>
          </div>
          <div class="overflow-hidden">
            <%= if Enum.empty?(@locations) and not @show_form do %>
              <div class="text-center py-8 text-zinc-500">
                <div class="mb-2">📍</div>
                <p>No locations yet.</p>
                <p class="text-sm">Add your first location to start monitoring.</p>
              </div>
            <% else %>
              <div class="max-h-96 overflow-y-auto">
                <%= if @show_form do %>
                  <div class="p-4 border-b border-zinc-200 dark:border-zinc-800 bg-blue-50 dark:bg-blue-950">
                    <form phx-submit="create_location" class="space-y-3">
                      <div>
                        <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                          Name
                        </label>
                        <input
                          type="text"
                          name="name"
                          placeholder="Home, Office, etc."
                          class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                          required
                        />
                      </div>
                      <div class="grid grid-cols-2 gap-2">
                        <div>
                          <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                            Latitude
                          </label>
                          <input
                            type="number"
                            name="latitude"
                            id="latitude-input"
                            step="0.000001"
                            placeholder="37.7749"
                            class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                            required
                          />
                        </div>
                        <div>
                          <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                            Longitude
                          </label>
                          <input
                            type="number"
                            name="longitude"
                            id="longitude-input"
                            step="0.000001"
                            placeholder="-122.4194"
                            class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                            required
                          />
                        </div>
                      </div>
                      <div>
                        <button
                          type="button"
                          id="use-my-location"
                          phx-hook="Geolocation"
                          class="inline-flex items-center rounded-md bg-zinc-700 px-3 py-1 text-white text-xs font-medium shadow hover:bg-zinc-800 transition-colors"
                        >
                          📍 Use My Location
                        </button>
                        <p class="mt-2 text-xs text-zinc-500 dark:text-zinc-400">
                          You can also click on the map to set the coordinates.
                        </p>
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                          Radius (km)
                        </label>
                        <div class="flex items-center gap-2">
                          <input
                            id="radius-input"
                            name="radius"
                            type="range"
                            min="10000"
                            max="500000"
                            step="10000"
                            value="50000"
                            class="flex-1 accent-blue-600"
                            phx-hook="RadiusPreview"
                          />
                          <input
                            id="radius-number"
                            type="number"
                            min="10"
                            step="10"
                            name="radius_km"
                            value="50"
                            class="w-16 px-2 py-1 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                          />
                        </div>
                      </div>
                      <div class="flex gap-2">
                        <button
                          type="submit"
                          disabled={@creating_location}
                          class="flex-1 inline-flex items-center justify-center rounded-md bg-blue-600 px-3 py-2 text-white text-sm font-medium shadow hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                        >
                          <%= if @creating_location do %>
                            <div class="inline-block animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2">
                            </div>
                            Adding...
                          <% else %>
                            Add Location
                          <% end %>
                        </button>
                        <button
                          type="button"
                          phx-click="hide_form"
                          disabled={@creating_location}
                          class="flex-1 inline-flex items-center justify-center rounded-md bg-zinc-500 px-3 py-2 text-white text-sm font-medium shadow hover:bg-zinc-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                        >
                          Cancel
                        </button>
                      </div>
                    </form>
                  </div>
                <% end %>
                <%= for location <- @locations do %>
                  <%= if @editing_location_id == location.id do %>
                    <% display_location =
                      get_display_location(location, @updating_location_id, @updating_location_data) %>
                    <div class="p-4 border-b border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900">
                      <form
                        id={"edit-location-form-#{location.id}"}
                        phx-submit="update_location"
                        class="space-y-3"
                      >
                        <input type="hidden" name="_id" value={location.id} />
                        <div>
                          <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                            Name
                          </label>
                          <input
                            type="text"
                            name="name"
                            value={display_location.name}
                            class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                            required
                          />
                        </div>
                        <div class="grid grid-cols-2 gap-2">
                          <div>
                            <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                              Latitude
                            </label>
                            <input
                              id={"edit-latitude-input-#{location.id}"}
                              type="number"
                              step="0.000001"
                              name="latitude"
                              value={display_location.latitude}
                              class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                              required
                            />
                          </div>
                          <div>
                            <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                              Longitude
                            </label>
                            <input
                              id={"edit-longitude-input-#{location.id}"}
                              type="number"
                              step="0.000001"
                              name="longitude"
                              value={display_location.longitude}
                              class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                              required
                            />
                          </div>
                        </div>
                        <div>
                          <button
                            type="button"
                            id={"use-my-location-edit-#{location.id}"}
                            phx-hook="Geolocation"
                            class="inline-flex items-center rounded-md bg-zinc-700 px-3 py-1 text-white text-xs font-medium shadow hover:bg-zinc-800 transition-colors"
                          >
                            📍 Use My Location
                          </button>
                        </div>
                        <div>
                          <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                            Radius (km)
                          </label>
                          <div class="flex items-center gap-2">
                            <input
                              id={"edit-radius-input-#{location.id}"}
                              name="radius"
                              type="range"
                              min="10000"
                              max="500000"
                              step="10000"
                              value={display_location.radius}
                              class="flex-1 accent-blue-600"
                              phx-hook="RadiusPreview"
                            />
                            <input
                              id={"edit-radius-number-#{location.id}"}
                              type="number"
                              min="10"
                              step="10"
                              name="radius_km"
                              value={div(display_location.radius, 1000)}
                              class="w-16 px-2 py-1 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                            />
                          </div>
                        </div>
                        <div class="flex gap-2">
                          <button
                            type="submit"
                            disabled={
                              @updating_location_id != nil and
                                to_string(@updating_location_id) == to_string(location.id)
                            }
                            class="flex-1 inline-flex items-center justify-center rounded-md bg-emerald-600 px-3 py-2 text-white text-sm font-medium shadow hover:bg-emerald-700 disabled:opacity-50 disabled:cursor-not-allowed"
                          >
                            <%= if @updating_location_id != nil and to_string(@updating_location_id) == to_string(location.id) do %>
                              <div class="inline-block animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2">
                              </div>
                              Saving...
                            <% else %>
                              Save
                            <% end %>
                          </button>
                          <button
                            type="button"
                            phx-click="cancel_edit_location"
                            disabled={
                              @updating_location_id != nil and
                                to_string(@updating_location_id) == to_string(location.id)
                            }
                            class="flex-1 inline-flex items-center justify-center rounded-md bg-zinc-500 px-3 py-2 text-white text-sm font-medium shadow hover:bg-zinc-600 disabled:opacity-50 disabled:cursor-not-allowed"
                          >
                            Cancel
                          </button>
                        </div>
                      </form>
                    </div>
                  <% else %>
                    <div class="p-4 border-b border-zinc-200 dark:border-zinc-800 hover:bg-zinc-50 dark:hover:bg-zinc-900 transition-colors">
                      <div class="flex items-start justify-between gap-3">
                        <div
                          class="flex-1 min-w-0 cursor-pointer"
                          phx-click="center_map_on_location"
                          phx-value-lat={location.latitude}
                          phx-value-lng={location.longitude}
                          phx-value-radius={location.radius}
                          phx-value-location-id={location.id}
                        >
                          <h4 class="font-medium text-zinc-900 dark:text-zinc-100 truncate">
                            {location.name}
                          </h4>
                          <p class="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                            {Float.round(location.latitude, 3)}, {Float.round(location.longitude, 3)}
                          </p>
                          <p class="text-xs text-zinc-500 dark:text-zinc-500 mt-1">
                            {div(location.radius, 1000)}km radius
                          </p>
                        </div>
                        <div class="flex items-center gap-1">
                          <button
                            phx-click="start_edit_location"
                            phx-value-id={location.id}
                            class="p-1 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 transition-colors"
                          >
                            ✏️
                          </button>
                          <button
                            phx-click="delete_location"
                            phx-value-id={location.id}
                            disabled={
                              @deleting_location_id != nil and
                                to_string(@deleting_location_id) == to_string(location.id)
                            }
                            class="p-1 text-zinc-400 hover:text-rose-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                            data-confirm="Are you sure you want to delete this location?"
                          >
                            <%= if @deleting_location_id != nil and to_string(@deleting_location_id) == to_string(location.id) do %>
                              <div class="inline-block animate-spin rounded-full h-3 w-3 border border-zinc-400 border-b-transparent">
                              </div>
                            <% else %>
                              🗑️
                            <% end %>
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
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
      
    <!-- Notification Devices and Settings -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Notification Devices Widget -->
        <.live_component
          module={AppWeb.Components.NotificationDevices}
          id="notification-devices"
          current_user={@current_user}
        />
        
    <!-- Settings Card -->
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
      
    <!-- Notification History -->
      <div class="grid grid-cols-1 gap-6">
        <.live_component
          module={AppWeb.Components.NotificationHistory}
          id="notification-history"
          current_user={@current_user}
          limit={10}
        />
      </div>
    </div>
    """
  end
end
