defmodule AppWeb.AuthLive.Dashboard do
  use AppWeb, :live_view
  alias App.Location

  def mount(_params, _session, socket) do
    # current_user is set by the on_mount hook
    locations = Location.list_for_user(socket.assigns.current_user.id)
    fires = App.Fire.recent_fires_near_locations(locations, 24, quality: :high)
    incidents = App.FireIncident.incidents_from_fires(fires)

    socket =
      socket
      |> assign(:locations, locations)
      |> assign(:fires, fires)
      |> assign(:incidents, incidents)
      |> assign(:show_form, false)
      |> assign(:form, to_form(%{}))
      |> assign(:editing_location_id, nil)
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
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("create_location", params, socket) do
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
         |> put_flash(:info, "Location added successfully!")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Error creating location")}
    end
  end

  def handle_event("delete_location", %{"id" => id}, socket) do
    location = App.Repo.get(Location, id)

    case Location.delete_location(location) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_locations_and_fires()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error deleting location")}
    end
  end

  def handle_event("start_edit_location", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_location_id, id)}
  end

  def handle_event("cancel_edit_location", _params, socket) do
    {:noreply, assign(socket, :editing_location_id, nil)}
  end

  def handle_event("update_location", params, socket) do
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
         |> put_flash(:info, "Location updated successfully!")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Error updating location")}
    end
  end

  def handle_event("center_map_on_incident", params, socket) do
    lat = parse_float(params["lat"])
    lng = parse_float(params["lng"])
    incident_id = params["incident-id"]

    # Push event to center map on the incident location
    {:noreply,
     socket
     |> push_event("center_map", %{
       latitude: lat,
       longitude: lng,
       # Zoom in closer to see the incident area
       zoom: 14,
       incident_id: incident_id,
       type: "incident"
     })}
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

  defp reload_locations_and_fires(socket) do
    locations = Location.list_for_user(socket.assigns.current_user.id)
    fires = App.Fire.recent_fires_near_locations(locations, 24, quality: :high)
    incidents = App.FireIncident.incidents_from_fires(fires)

    socket
    |> assign(:locations, locations)
    |> assign(:fires, fires)
    |> assign(:incidents, incidents)
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

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
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
      <!-- Single card: Monitored Locations (map + form + list) -->
      <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
        <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Monitored Locations</h2>
          <button
            phx-click="show_form"
            class="inline-flex items-center rounded-md bg-blue-600 px-3 py-1.5 text-white text-sm font-medium shadow hover:bg-blue-700"
          >
            + Add Location
          </button>
        </div>
        <div class="p-4 space-y-4">
          <div
            id="locations-map"
            phx-hook="Map"
            phx-update="ignore"
            data-editing-id={@editing_location_id}
            class="h-[400px] w-full rounded-md"
          >
          </div>

          <%= if @show_form do %>
            <div class="p-4 bg-zinc-50 dark:bg-zinc-900 rounded-lg border border-zinc-200 dark:border-zinc-800">
              <form phx-submit="create_location" class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                    Name
                  </label>
                  <input
                    type="text"
                    name="name"
                    placeholder="Home, Office, etc."
                    class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
                    required
                  />
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
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
                      class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
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
                      class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
                      required
                    />
                  </div>
                </div>
                <div>
                  <button
                    type="button"
                    id="use-my-location"
                    phx-hook="Geolocation"
                    class="inline-flex items-center rounded-md bg-zinc-700 px-3 py-2 text-white text-sm font-medium shadow hover:bg-zinc-800"
                  >
                    📍 Use My Location
                  </button>
                  <p class="mt-2 text-xs text-zinc-500 dark:text-zinc-400">
                    Tip: You can also click on the map to set the coordinates.
                  </p>
                </div>
                <div>
                  <label
                    for="radius-input"
                    class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1"
                  >
                    Radius (km)
                  </label>
                  <div class="flex items-center gap-3">
                    <input
                      id="radius-input"
                      name="radius"
                      type="range"
                      min="10000"
                      max="500000"
                      step="10000"
                      value="50000"
                      class="w-full accent-blue-600"
                      phx-hook="RadiusPreview"
                    />
                    <input
                      id="radius-number"
                      type="number"
                      min="10"
                      step="10"
                      name="radius_km"
                      value="50"
                      class="w-28 px-2 py-1 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
                    />
                  </div>
                  <div class="text-xs text-zinc-600 dark:text-zinc-300 mt-1">
                    Selected radius: <span id="radius-value">50</span> km
                  </div>
                </div>
                <div class="flex gap-2">
                  <button
                    type="submit"
                    class="inline-flex items-center rounded-md bg-emerald-600 px-4 py-2 text-white text-sm font-medium shadow hover:bg-emerald-700"
                  >
                    Add Location
                  </button>
                  <button
                    type="button"
                    phx-click="hide_form"
                    class="inline-flex items-center rounded-md bg-zinc-500 px-4 py-2 text-white text-sm font-medium shadow hover:bg-zinc-600"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </div>
          <% end %>

          <%= if Enum.empty?(@locations) do %>
            <div class="text-center py-8 text-zinc-500">
              <p>No locations added yet.</p>
              <p class="text-sm">Add a location to start monitoring for wildfires.</p>
            </div>
          <% else %>
            <ul class="space-y-3">
              <%= for location <- @locations do %>
                <li
                  class="p-3 bg-zinc-50 dark:bg-zinc-900 rounded-lg border border-zinc-200 dark:border-zinc-800 cursor-pointer hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
                  phx-click="center_map_on_location"
                  phx-value-lat={location.latitude}
                  phx-value-lng={location.longitude}
                  phx-value-radius={location.radius}
                  phx-value-location-id={location.id}
                >
                  <%= if @editing_location_id == location.id do %>
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
                          value={location.name}
                          class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
                          required
                        />
                      </div>
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <div>
                          <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                            Latitude
                          </label>
                          <input
                            id={"edit-latitude-input-#{location.id}"}
                            type="number"
                            step="0.000001"
                            name="latitude"
                            value={location.latitude}
                            class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
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
                            value={location.longitude}
                            class="w-full px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
                            required
                          />
                        </div>
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-1">
                          Radius (km)
                        </label>
                        <div class="flex items-center gap-3">
                          <input
                            id={"edit-radius-input-#{location.id}"}
                            name="radius"
                            type="range"
                            min="10000"
                            max="500000"
                            step="10000"
                            value={location.radius}
                            class="w-full accent-blue-600"
                          />
                          <input
                            id={"edit-radius-number-#{location.id}"}
                            type="number"
                            min="10"
                            step="10"
                            name="radius_km"
                            value={div(location.radius, 1000)}
                            class="w-28 px-2 py-1 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0"
                          />
                        </div>
                        <div class="text-xs text-zinc-600 dark:text-zinc-300 mt-1">
                          Selected radius:
                          <span id={"edit-radius-value-#{location.id}"}>
                            {div(location.radius, 1000)}
                          </span>
                          km
                        </div>
                      </div>
                      <div class="flex gap-2">
                        <button
                          type="submit"
                          class="inline-flex items-center rounded-md bg-emerald-600 px-4 py-2 text-white text-sm font-medium shadow hover:bg-emerald-700"
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_edit_location"
                          class="inline-flex items-center rounded-md bg-zinc-500 px-4 py-2 text-white text-sm font-medium shadow hover:bg-zinc-600"
                        >
                          Cancel
                        </button>
                      </div>
                    </form>
                  <% else %>
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <h4 class="font-medium text-zinc-900 dark:text-zinc-100">{location.name}</h4>
                        <p class="text-sm text-zinc-600">
                          {Float.round(location.latitude, 4)}, {Float.round(location.longitude, 4)}
                        </p>
                        <p class="text-sm text-zinc-600">
                          {location.radius} meter radius
                        </p>
                        <p class="text-xs text-zinc-400 dark:text-zinc-500 mt-1">
                          👆 Click to view on map
                        </p>
                      </div>
                      <div class="flex items-center gap-2">
                        <button
                          phx-click="start_edit_location"
                          phx-value-id={location.id}
                          class="text-zinc-700 hover:text-zinc-900 dark:text-zinc-300 dark:hover:text-zinc-100"
                        >
                          ✏️
                        </button>
                        <button
                          phx-click="delete_location"
                          phx-value-id={location.id}
                          class="text-rose-600 hover:text-rose-700"
                          data-confirm="Are you sure you want to delete this location?"
                        >
                          🗑️
                        </button>
                      </div>
                    </div>
                  <% end %>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Fire Incidents Widget -->
        <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
          <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
              Active Fire Incidents
            </h2>
            <span class="inline-flex items-center rounded-full bg-red-100 dark:bg-red-900/20 px-2.5 py-0.5 text-xs font-medium text-red-800 dark:text-red-400">
              {length(@incidents)} active
            </span>
          </div>
          <div class="p-4">
            <%= if Enum.empty?(@incidents) do %>
              <div class="text-center py-8 text-zinc-500">
                <div class="mb-2">🔥</div>
                <p>No active fire incidents in your monitored areas.</p>
                <p class="text-sm">This is good news!</p>
              </div>
            <% else %>
              <div class="space-y-3 max-h-96 overflow-y-auto">
                <%= for incident <- @incidents do %>
                  <div
                    class="p-3 bg-red-50 dark:bg-red-900/10 rounded-lg border border-red-200 dark:border-red-800/30 cursor-pointer hover:bg-red-100 dark:hover:bg-red-900/20 transition-colors"
                    phx-click="center_map_on_incident"
                    phx-value-lat={incident.center_latitude}
                    phx-value-lng={incident.center_longitude}
                    phx-value-incident-id={incident.id}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div class="flex-1">
                        <div class="flex items-center gap-2 mb-1">
                          <span class="inline-flex items-center rounded-full bg-red-100 dark:bg-red-900/30 px-2 py-0.5 text-xs font-medium text-red-800 dark:text-red-400">
                            {incident.status}
                          </span>
                          <span class="text-sm text-zinc-600 dark:text-zinc-400">
                            {incident.fire_count} fire{if incident.fire_count != 1, do: "s"}
                          </span>
                          <span class="text-xs text-zinc-500 dark:text-zinc-400 font-mono">
                            ID: {String.slice(incident.id, 0, 8)}...
                          </span>
                        </div>
                        <p class="text-sm text-zinc-700 dark:text-zinc-300 mb-1">
                          📍 {Float.round(incident.center_latitude, 4)}, {Float.round(
                            incident.center_longitude,
                            4
                          )}
                        </p>
                        <div class="text-xs text-zinc-500 dark:text-zinc-400 space-y-1">
                          <div>
                            <strong>First detected:</strong> {format_datetime(
                              incident.first_detected_at
                            )}
                          </div>
                          <div>
                            <strong>Last activity:</strong> {format_datetime(
                              incident.last_detected_at
                            )}
                          </div>
                          <%= if incident.max_frp do %>
                            <div>
                              <strong>Max intensity:</strong> {Float.round(incident.max_frp, 1)} MW
                            </div>
                          <% end %>
                          <%= if incident.avg_frp do %>
                            <div>
                              <strong>Avg intensity:</strong> {Float.round(incident.avg_frp, 1)} MW
                            </div>
                          <% end %>
                        </div>
                      </div>
                      <div class="text-right">
                        <div class="text-xs text-zinc-500 dark:text-zinc-400">
                          {time_ago(incident.last_detected_at)}
                        </div>
                        <div class="text-xs text-zinc-400 dark:text-zinc-500 mt-1">
                          👆 Click to view on map
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

    <!-- Settings -->
        <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
          <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
            <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Settings</h2>
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
