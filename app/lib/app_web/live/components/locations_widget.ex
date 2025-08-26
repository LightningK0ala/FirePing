defmodule AppWeb.Components.LocationsWidget do
  use AppWeb, :live_component
  alias App.Location

  def handle_event("show_add_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, true)
     |> assign_new(:draft_latitude, fn -> nil end)
     |> assign_new(:draft_longitude, fn -> nil end)}
  end

  def handle_event("hide_add_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_modal, false)}
  end

  def handle_event("start_pick_on_map", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, false)
     |> push_event("start_pick_on_map", %{})}
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
        locations = Location.list_for_user(socket.assigns.current_user.id)
        # Notify parent LiveView to refresh locations/fires
        send(self(), {:location_updated})

        {:noreply,
         socket
         |> assign(:locations, locations)
         |> assign(:show_add_modal, false)
         |> push_event("clear_radius_preview", %{})
         |> put_flash(:info, "Location added successfully!")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete_location", %{"id" => id}, socket) do
    location = App.Repo.get(Location, id)

    case Location.delete_location(location) do
      {:ok, _} ->
        locations = Location.list_for_user(socket.assigns.current_user.id)
        # Send message to parent to reload locations and fires
        send(self(), {:location_updated})

        {:noreply,
         socket
         |> assign(:locations, locations)
         |> put_flash(:info, "Location deleted successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete location")}
    end
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
        locations = Location.list_for_user(socket.assigns.current_user.id)
        # Send message to parent to reload locations and fires
        send(self(), {:location_updated})

        {:noreply,
         socket
         |> assign(:locations, locations)
         |> assign(:editing_location_id, nil)
         |> push_event("clear_radius_preview", %{})
         |> put_flash(:info, "Location updated successfully!")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Error updating location")}
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

  def update(%{action: :close_modal}, socket) do
    {:ok, assign(socket, :show_add_modal, false)}
  end

  def update(%{action: :show_modal}, socket) do
    {:ok, assign(socket, :show_add_modal, true)}
  end

  def update(%{action: :prefill_coords, latitude: lat, longitude: lng}, socket) do
    {:ok,
     socket
     |> assign(:draft_latitude, lat)
     |> assign(:draft_longitude, lng)
     |> assign(:show_add_modal, true)}
  end

  def update(%{action: :location_created}, socket) do
    locations = Location.list_for_user(socket.assigns.current_user.id)

    {:ok,
     socket
     |> assign(:locations, locations)
     |> assign(:show_add_modal, false)
     |> put_flash(:info, "Location added successfully!")}
  end

  def update(assigns, socket) do
    locations = Location.list_for_user(assigns.current_user.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:locations, locations)
     |> assign(:show_add_modal, false)
     |> assign_new(:draft_latitude, fn -> nil end)
     |> assign_new(:draft_longitude, fn -> nil end)
     |> assign(:editing_location_id, nil)}
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

  def render(assigns) do
    ~H"""
    <div class="bg-white dark:bg-zinc-950 rounded-lg shadow-sm ring-1 ring-zinc-200 dark:ring-zinc-800">
      <div class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Your Locations</h2>
          <button
            phx-click="show_add_modal"
            phx-target={@myself}
            class="inline-flex items-center px-3 py-1.5 text-sm font-medium text-blue-600 hover:text-blue-700 border border-blue-200 dark:border-blue-700 rounded-md hover:bg-blue-50 dark:hover:bg-blue-950/20 transition-colors"
          >
            + Add
          </button>
        </div>
      </div>
      <div class="overflow-hidden">
        <%= if Enum.empty?(@locations) do %>
          <div class="text-center py-8">
            <div class="text-4xl mb-2">📍</div>
            <div class="text-zinc-500 dark:text-zinc-400 mb-4">No locations added yet</div>
            <button
              phx-click="show_add_modal"
              phx-target={@myself}
              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700 transition-colors"
            >
              Add Your First Location
            </button>
          </div>
        <% else %>
          <div class="max-h-96 overflow-y-auto">
            <div class="p-4 space-y-3">
              <%= for location <- @locations do %>
                <%= if @editing_location_id == location.id do %>
                  <div class="p-4 border border-zinc-200 dark:border-zinc-700 rounded-lg bg-zinc-50 dark:bg-zinc-900">
                    <form
                      id={"edit-location-form-#{location.id}"}
                      phx-submit="update_location"
                      phx-target={@myself}
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
                          class="w-full px-3 py-2 text-sm border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded focus:border-blue-400 focus:ring-1 focus:ring-blue-400"
                          required
                          autofocus
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
                            value={location.latitude}
                            class="w-full px-3 py-2 text-sm border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded focus:border-blue-400 focus:ring-1 focus:ring-blue-400"
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
                            class="w-full px-3 py-2 text-sm border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded focus:border-blue-400 focus:ring-1 focus:ring-blue-400"
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
                            value={location.radius}
                            class="flex-1 accent-blue-600"
                            phx-hook="RadiusPreview"
                          />
                          <input
                            id={"edit-radius-number-#{location.id}"}
                            type="number"
                            min="10"
                            step="10"
                            name="radius_km"
                            value={div(location.radius, 1000)}
                            class="w-16 px-2 py-1 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-zinc-400 focus:ring-0 text-sm"
                          />
                        </div>
                      </div>
                      <div class="flex gap-2">
                        <button
                          type="submit"
                          class="flex-1 px-3 py-2 text-xs bg-green-600 text-white rounded hover:bg-green-700"
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_edit_location"
                          phx-target={@myself}
                          class="flex-1 px-3 py-2 text-xs bg-gray-500 text-white rounded hover:bg-gray-600"
                        >
                          Cancel
                        </button>
                      </div>
                    </form>
                  </div>
                <% else %>
                  <div class="p-3 border border-zinc-200 dark:border-zinc-700 rounded-lg">
                    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                      <div
                        class="flex-1 min-w-0 cursor-pointer"
                        phx-click="center_map_on_location"
                        phx-value-lat={location.latitude}
                        phx-value-lng={location.longitude}
                        phx-value-radius={location.radius}
                        phx-value-location-id={location.id}
                        phx-target={@myself}
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
                          phx-target={@myself}
                          class="p-1 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 transition-colors"
                          title="Edit location"
                        >
                          ✏️
                        </button>
                        <button
                          phx-click="delete_location"
                          phx-value-id={location.id}
                          phx-target={@myself}
                          data-confirm="Are you sure you want to delete this location?"
                          class="p-1 text-zinc-400 hover:text-rose-600 transition-colors"
                          title="Delete location"
                        >
                          🗑️
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @show_add_modal do %>
        <.live_component
          module={AppWeb.Components.Modal}
          id="add-location-modal"
          parent_component={__MODULE__}
          parent_id="locations-widget"
          title="Add New Location"
          max_width="max-w-lg"
        >
          <form phx-submit="create_location" phx-target={@myself} class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2">
                Location Name
              </label>
              <input
                type="text"
                name="name"
                placeholder="Home, Office, Vacation House, etc."
                class="w-full px-3 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-blue-400 focus:ring-1 focus:ring-blue-400 text-sm"
                required
              />
            </div>

            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2">
                  Latitude
                </label>
                <input
                  type="number"
                  name="latitude"
                  id="modal-latitude-input"
                  step="0.000001"
                  placeholder="37.7749"
                  class="w-full px-3 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-blue-400 focus:ring-1 focus:ring-blue-400 text-sm"
                  value={@draft_latitude}
                  required
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2">
                  Longitude
                </label>
                <input
                  type="number"
                  name="longitude"
                  id="modal-longitude-input"
                  step="0.000001"
                  placeholder="-122.4194"
                  class="w-full px-3 py-2.5 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-blue-400 focus:ring-1 focus:ring-blue-400 text-sm"
                  value={@draft_longitude}
                  required
                />
              </div>
            </div>

            <div>
              <button
                type="button"
                id="modal-use-my-location"
                phx-hook="Geolocation"
                class="inline-flex items-center rounded-md bg-zinc-700 px-3 py-2 text-white text-sm font-medium shadow hover:bg-zinc-800 transition-colors"
              >
                📍 Use My Location
              </button>
              <button
                type="button"
                phx-click="start_pick_on_map"
                phx-target={@myself}
                class="inline-flex items-center rounded-md bg-blue-600 px-3 py-2 text-white text-sm font-medium shadow hover:bg-blue-700 transition-colors ml-2"
              >
                🗺️ Pick on map
              </button>
              <p class="mt-2 text-xs text-zinc-500 dark:text-zinc-400">
                You can also click on the map to set the coordinates.
              </p>
            </div>

            <div>
              <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-200 mb-2">
                Monitoring Radius (km)
              </label>
              <div class="flex items-center gap-3">
                <input
                  id="modal-radius-input"
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
                  id="modal-radius-number"
                  type="number"
                  min="10"
                  step="10"
                  name="radius_km"
                  value="50"
                  class="w-20 px-3 py-2 border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-md focus:border-blue-400 focus:ring-1 focus:ring-blue-400 text-sm"
                />
              </div>
              <p class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
                This area will be monitored for fire activity
              </p>
            </div>

            <div class="flex gap-3 pt-4">
              <button
                type="submit"
                class="flex-1 inline-flex items-center justify-center px-4 py-2.5 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
              >
                Add Location
              </button>
              <button
                type="button"
                phx-click="hide_add_modal"
                phx-target={@myself}
                class="flex-1 inline-flex items-center justify-center px-4 py-2.5 bg-zinc-500 text-white text-sm font-medium rounded-md hover:bg-zinc-600 transition-colors focus:outline-none focus:ring-2 focus:ring-zinc-500 focus:ring-offset-2"
              >
                Cancel
              </button>
            </div>
          </form>
        </.live_component>
      <% end %>
    </div>
    """
  end
end
