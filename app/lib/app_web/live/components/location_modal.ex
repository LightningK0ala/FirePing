defmodule AppWeb.Components.LocationModal do
  use AppWeb, :live_component
  alias App.Location

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
        # Send success message to parent
        send_update(AppWeb.Components.LocationsWidget,
          id: "locations-widget",
          current_user: socket.assigns.current_user,
          action: :location_created
        )

        # Send message to parent to reload locations and fires
        send(self(), {:location_updated})

        # Close the modal
        send_update(AppWeb.Components.Modal,
          id: "add-location-modal",
          action: :close_modal
        )

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("close_modal", _params, socket) do
    # Send close event to parent
    send_update(AppWeb.Components.LocationsWidget,
      id: "locations-widget",
      current_user: socket.assigns.current_user,
      action: :close_modal
    )

    {:noreply, socket}
  end

  def update(%{action: :close_modal}, socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(%{}))}
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {float, _} -> float
      :error -> String.to_integer(str) * 1.0
    end
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={AppWeb.Components.Modal}
      id="add-location-modal"
      title="Add New Location"
      max_width="max-w-lg"
      parent_component={AppWeb.Components.LocationsWidget}
      parent_id="locations-widget"
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
            phx-click="close_modal"
            phx-target={@myself}
            class="flex-1 inline-flex items-center justify-center px-4 py-2.5 bg-zinc-500 text-white text-sm font-medium rounded-md hover:bg-zinc-600 transition-colors focus:outline-none focus:ring-2 focus:ring-zinc-500 focus:ring-offset-2"
          >
            Cancel
          </button>
        </div>
      </form>
    </.live_component>
    """
  end
end
