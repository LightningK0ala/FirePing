defmodule App.FireTest do
  use App.DataCase
  import App.Factory
  import Mock
  alias App.Fire

  @sample_nasa_data %{
    "latitude" => 66.59672,
    "longitude" => 76.99258,
    "bright_ti4" => 338.39,
    "scan" => 0.79,
    "track" => 0.78,
    "acq_date" => "2025-08-07",
    "acq_time" => 105,
    "satellite" => "N21",
    "instrument" => "VIIRS",
    "confidence" => "n",
    "version" => "2.0NRT",
    "bright_ti5" => 284.88,
    "frp" => 7.55,
    "daynight" => "D"
  }

  describe "changeset/2" do
    test "creates valid changeset with NASA data" do
      nasa_data_with_datetime = Map.put(@sample_nasa_data, "detected_at", ~U[2025-08-07 01:05:00Z])
      changeset = Fire.changeset(%Fire{}, nasa_data_with_datetime)
      
      assert changeset.valid?
      assert get_field(changeset, :latitude) == 66.59672
      assert get_field(changeset, :longitude) == 76.99258
      assert get_field(changeset, :confidence) == "n"
      assert get_field(changeset, :satellite) == "N21"
      assert get_field(changeset, :frp) == 7.55
    end

    test "requires required fields" do
      changeset = Fire.changeset(%Fire{}, %{})
      
      refute changeset.valid?
      assert changeset.errors[:latitude]
      assert changeset.errors[:longitude]
      assert changeset.errors[:detected_at]
      assert changeset.errors[:confidence]
      assert changeset.errors[:satellite]
    end

    test "validates latitude bounds" do
      invalid_data = Map.put(@sample_nasa_data, "latitude", 95.0)
      changeset = Fire.changeset(%Fire{}, invalid_data)
      
      refute changeset.valid?
      assert changeset.errors[:latitude]
    end

    test "validates longitude bounds" do
      invalid_data = Map.put(@sample_nasa_data, "longitude", 185.0)
      changeset = Fire.changeset(%Fire{}, invalid_data)
      
      refute changeset.valid?
      assert changeset.errors[:longitude]
    end

    test "creates PostGIS point from coordinates" do
      nasa_data_with_datetime = Map.put(@sample_nasa_data, "detected_at", ~U[2025-08-07 01:05:00Z])
      changeset = Fire.changeset(%Fire{}, nasa_data_with_datetime)
      
      assert changeset.valid?
      point = get_field(changeset, :point)
      assert %Geo.Point{} = point
      assert point.coordinates == {76.99258, 66.59672}  # lng, lat order
      assert point.srid == 4326
    end
  end

  describe "parse_nasa_datetime/2" do
    test "converts NASA date and time to UTC datetime" do
      {:ok, datetime} = Fire.parse_nasa_datetime("2025-08-07", 105)
      
      assert datetime == ~U[2025-08-07 01:05:00Z]
    end

    test "handles different time formats" do
      {:ok, datetime1} = Fire.parse_nasa_datetime("2025-08-07", 1842)
      assert datetime1 == ~U[2025-08-07 18:42:00Z]
      
      {:ok, datetime2} = Fire.parse_nasa_datetime("2025-08-07", 45)
      assert datetime2 == ~U[2025-08-07 00:45:00Z]
    end

    test "returns error for invalid date" do
      {:error, _reason} = Fire.parse_nasa_datetime("invalid-date", 105)
    end
  end

  describe "generate_nasa_id/1" do
    test "creates unique identifier from fire data" do
      nasa_id = Fire.generate_nasa_id(@sample_nasa_data)
      
      assert is_binary(nasa_id)
      assert nasa_id =~ "66.5967"  # latitude
      assert nasa_id =~ "76.9926"  # longitude  
      assert nasa_id =~ "2025-08-07"  # date
      assert nasa_id =~ "105"  # time
      assert nasa_id =~ "N21"  # satellite
    end

    test "generates same ID for identical data" do
      nasa_id1 = Fire.generate_nasa_id(@sample_nasa_data)
      nasa_id2 = Fire.generate_nasa_id(@sample_nasa_data)
      
      assert nasa_id1 == nasa_id2
    end

    test "generates different IDs for different coordinates" do
      data1 = @sample_nasa_data
      data2 = Map.put(@sample_nasa_data, "latitude", 67.0)
      
      nasa_id1 = Fire.generate_nasa_id(data1)
      nasa_id2 = Fire.generate_nasa_id(data2)
      
      assert nasa_id1 != nasa_id2
    end
  end

  describe "create_from_nasa_data/1" do
    test "creates fire from NASA CSV row data" do
      assert {:ok, fire} = Fire.create_from_nasa_data(@sample_nasa_data)
      
      assert fire.latitude == 66.59672
      assert fire.longitude == 76.99258
      assert fire.confidence == "n"
      assert fire.satellite == "N21"
      assert fire.instrument == "VIIRS"
      assert fire.frp == 7.55
      assert fire.detected_at == ~U[2025-08-07 01:05:00Z]
      assert fire.nasa_id
    end

    test "prevents duplicate fires with same NASA ID" do
      assert {:ok, _fire1} = Fire.create_from_nasa_data(@sample_nasa_data)
      assert {:error, changeset} = Fire.create_from_nasa_data(@sample_nasa_data)
      
      assert changeset.errors[:nasa_id]
    end
  end

  describe "high_quality?/1" do
    test "returns true for high quality fires" do
      fire = insert(:fire, confidence: "h", frp: 10.0)
      assert Fire.high_quality?(fire)
      
      fire = insert(:fire, confidence: "n", frp: 5.0)
      assert Fire.high_quality?(fire)
    end

    test "returns false for low quality fires" do
      fire = insert(:fire, confidence: "l", frp: 10.0)
      refute Fire.high_quality?(fire)
      
      fire = insert(:fire, confidence: "n", frp: 2.0)
      refute Fire.high_quality?(fire)
    end
  end

  describe "recent_fires/1" do
    test "returns fires from last N hours" do
      _old_fire = insert(:fire, detected_at: ~U[2025-08-06 10:00:00Z])
      recent_fire = insert(:fire, detected_at: ~U[2025-08-07 22:00:00Z])
      
      # Mock current time as 2025-08-07 23:00:00Z
      with_mock(DateTime, [:passthrough], [utc_now: fn -> ~U[2025-08-07 23:00:00Z] end]) do
        recent_fires = Fire.recent_fires(2)
        
        assert length(recent_fires) == 1
        assert hd(recent_fires).id == recent_fire.id
      end
    end
  end

  describe "near_location/3" do
    test "finds fires within radius of coordinates" do
      # Fire in Portugal (close to sample location)
      close_fire = insert(:fire, 
        latitude: 41.131, 
        longitude: -8.629
      )
      
      # Fire in Spain (far from sample location)  
      far_fire = insert(:fire,
        latitude: 40.416,
        longitude: -3.703
      )
      
      # Search near Porto, Portugal with 10km radius
      nearby_fires = Fire.near_location(41.130, -8.628, 10000)
      
      fire_ids = Enum.map(nearby_fires, &(&1.id))
      assert close_fire.id in fire_ids
      refute far_fire.id in fire_ids
    end
  end

  describe "cleanup_old/1" do
    test "deletes fires older than specified days" do
      old_fire = insert(:fire, detected_at: ~U[2025-08-01 10:00:00Z])
      recent_fire = insert(:fire, detected_at: ~U[2025-08-07 10:00:00Z])
      
      # Mock current time as 2025-08-07 23:00:00Z
      with_mock(DateTime, [:passthrough], [utc_now: fn -> ~U[2025-08-07 23:00:00Z] end]) do
        {deleted_count, _} = Fire.cleanup_old(5)  # Delete fires older than 5 days
        
        assert deleted_count == 1
        assert App.Repo.get(Fire, recent_fire.id)
        refute App.Repo.get(Fire, old_fire.id)
      end
    end
  end

  describe "bulk_insert/1" do
    test "efficiently inserts multiple fires from NASA data" do
      nasa_data_list = [
        @sample_nasa_data,
        Map.merge(@sample_nasa_data, %{"latitude" => 67.0, "acq_time" => 106}),
        Map.merge(@sample_nasa_data, %{"latitude" => 68.0, "acq_time" => 107})
      ]
      
      {inserted_count, _} = Fire.bulk_insert(nasa_data_list)
      
      assert inserted_count == 3
      assert App.Repo.aggregate(Fire, :count) == 3
    end

    test "handles duplicate NASA IDs gracefully in bulk insert" do
      nasa_data_list = [
        @sample_nasa_data,
        @sample_nasa_data,  # Duplicate
        Map.merge(@sample_nasa_data, %{"latitude" => 67.0})
      ]
      
      {inserted_count, _} = Fire.bulk_insert(nasa_data_list)
      
      # Should insert 2 unique records, skip 1 duplicate
      assert inserted_count == 2
    end
  end
end