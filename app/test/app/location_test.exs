defmodule App.LocationTest do
  use App.DataCase

  alias App.Location

  describe "changeset/2" do
    test "valid changeset with required fields" do
      user = insert(:user)

      attrs = %{
        name: "My Home",
        latitude: 40.7128,
        longitude: -74.0060,
        radius: 5000,
        user_id: user.id
      }

      changeset = Location.changeset(%Location{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without required fields" do
      changeset = Location.changeset(%Location{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).latitude
      assert "can't be blank" in errors_on(changeset).longitude
      assert "can't be blank" in errors_on(changeset).radius
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "invalid changeset with latitude out of range" do
      user = insert(:user)

      attrs = %{
        name: "Invalid Location",
        # Invalid: > 90
        latitude: 91.0,
        longitude: -74.0060,
        radius: 5000,
        user_id: user.id
      }

      changeset = Location.changeset(%Location{}, attrs)
      refute changeset.valid?
      assert "must be between -90 and 90" in errors_on(changeset).latitude
    end

    test "invalid changeset with longitude out of range" do
      user = insert(:user)

      attrs = %{
        name: "Invalid Location",
        latitude: 40.7128,
        # Invalid: > 180
        longitude: 181.0,
        radius: 5000,
        user_id: user.id
      }

      changeset = Location.changeset(%Location{}, attrs)
      refute changeset.valid?
      assert "must be between -180 and 180" in errors_on(changeset).longitude
    end

    test "invalid changeset with negative radius" do
      user = insert(:user)

      attrs = %{
        name: "Invalid Location",
        latitude: 40.7128,
        longitude: -74.0060,
        # Invalid: negative
        radius: -100,
        user_id: user.id
      }

      changeset = Location.changeset(%Location{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).radius
    end
  end

  describe "create_location/2" do
    test "creates location with valid attributes" do
      user = insert(:user)

      attrs = %{
        "name" => "San Francisco",
        "latitude" => 37.7749,
        "longitude" => -122.4194,
        "radius" => 10000
      }

      assert {:ok, location} = Location.create_location(user, attrs)
      assert location.name == "San Francisco"
      assert location.user_id == user.id
      assert location.latitude == 37.7749
      assert location.longitude == -122.4194
      # PostGIS geometry should be created
      assert location.point
    end

    test "returns error with invalid attributes" do
      user = insert(:user)
      attrs = %{name: "", latitude: nil}

      assert {:error, changeset} = Location.create_location(user, attrs)
      refute changeset.valid?
    end
  end

  describe "locations_for_user/1" do
    test "returns all locations for a user" do
      user1 = insert(:user)
      user2 = insert(:user)

      location1 = insert(:location, user: user1, name: "Home")
      location2 = insert(:location, user: user1, name: "Work")
      _location3 = insert(:location, user: user2, name: "Other")

      locations = Location.locations_for_user(user1)

      assert length(locations) == 2

      assert Enum.map(locations, & &1.id) |> Enum.sort() ==
               [location1.id, location2.id] |> Enum.sort()
    end

    test "returns empty list when user has no locations" do
      user = insert(:user)
      assert Location.locations_for_user(user) == []
    end
  end

  describe "within_radius/3" do
    test "finds locations within specified radius of point" do
      user = insert(:user)
      # NYC: 40.7128, -74.0060
      nyc_location =
        insert(:location,
          user: user,
          name: "NYC",
          latitude: 40.7128,
          longitude: -74.0060,
          radius: 5000
        )

      # Boston: ~300km from NYC
      _boston_location =
        insert(:location,
          user: user,
          name: "Boston",
          latitude: 42.3601,
          longitude: -71.0589,
          radius: 5000
        )

      # Fire near NYC (within 10km)
      fire_lat = 40.7200
      fire_lon = -74.0000

      nearby_locations = Location.within_radius(fire_lat, fire_lon, 10000)

      assert length(nearby_locations) == 1
      assert hd(nearby_locations).id == nyc_location.id
    end

    test "returns empty list when no locations within radius" do
      user = insert(:user)
      # NYC location
      _nyc_location =
        insert(:location,
          user: user,
          latitude: 40.7128,
          longitude: -74.0060,
          radius: 5000
        )

      # Fire in LA (very far from NYC)
      fire_lat = 34.0522
      fire_lon = -118.2437

      nearby_locations = Location.within_radius(fire_lat, fire_lon, 1000)
      assert nearby_locations == []
    end
  end

  describe "delete_location/1" do
    test "deletes location successfully" do
      user = insert(:user)
      location = insert(:location, user: user)

      assert {:ok, _deleted_location} = Location.delete_location(location)
      assert App.Repo.get(Location, location.id) == nil
    end
  end

  describe "update_location/2" do
    test "updates fields and regenerates point" do
      user = insert(:user)

      location =
        insert(:location,
          user: user,
          latitude: 40.7128,
          longitude: -74.0060,
          radius: 5000,
          name: "Home"
        )

      attrs = %{
        "name" => "New Home",
        "latitude" => 37.7749,
        "longitude" => -122.4194,
        "radius" => 8000
      }

      assert {:ok, updated} = Location.update_location(location, attrs)
      assert updated.name == "New Home"
      assert updated.latitude == 37.7749
      assert updated.longitude == -122.4194
      assert updated.radius == 8000
      # point should be regenerated with new coords
      assert match?(%Geo.Point{coordinates: {-122.4194, 37.7749}}, updated.point)
    end

    test "returns error changeset with invalid data" do
      user = insert(:user)
      location = insert(:location, user: user)

      # invalid latitude
      attrs = %{"latitude" => 200}
      assert {:error, changeset} = Location.update_location(location, attrs)
      refute changeset.valid?
    end
  end
end
