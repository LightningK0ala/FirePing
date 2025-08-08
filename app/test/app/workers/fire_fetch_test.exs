defmodule App.Workers.FireFetchTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo

  alias App.Workers.FireFetch
  alias App.{Fire, Repo}

  import Mock

  @sample_csv """
  latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,instrument,confidence,version,bright_ti5,frp,daynight
  37.7749,-122.4194,320.5,1.2,1.1,2023-08-07,1430,Terra,VIIRS,n,2.0NRT,295.3,15.2,D
  40.7589,-73.9851,315.8,1.3,1.0,2023-08-07,1445,Aqua,VIIRS,h,2.0NRT,290.1,12.4,D
  34.0522,-118.2437,305.2,0.9,1.2,2023-08-07,1500,Terra,VIIRS,l,2.0NRT,285.5,3.8,D
  """

  @high_quality_csv """
  latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,instrument,confidence,version,bright_ti5,frp,daynight
  37.7749,-122.4194,320.5,1.2,1.1,2023-08-07,1430,Terra,VIIRS,n,2.0NRT,295.3,15.2,D
  40.7589,-73.9851,315.8,1.3,1.0,2023-08-07,1445,Aqua,VIIRS,h,2.0NRT,290.1,12.4,D
  """

  describe "perform/1" do
    test "successfully processes VIIRS fire data" do
      with_mocks([
        {HTTPoison, [],
         [
           get: fn _url, _headers, _opts ->
             {:ok, %{status_code: 200, body: @high_quality_csv}}
           end
         ]}
      ]) do
        assert :ok = perform_job(FireFetch, %{"days_back" => 1})

        # Verify fires were created
        fires = Repo.all(Fire)
        assert length(fires) == 2

        # Verify fire data
        fire = List.first(fires)
        assert fire.latitude in [37.7749, 40.7589]
        assert fire.confidence in ["n", "h"]
        assert fire.frp >= 5.0
      end
    end

    test "persists all fires without filtering" do
      with_mocks([
        {HTTPoison, [],
         [
           get: fn _url, _headers, _opts ->
             {:ok, %{status_code: 200, body: @sample_csv}}
           end
         ]}
      ]) do
        assert :ok = perform_job(FireFetch, %{"days_back" => 1})

        # Should have all 3 fires persisted (no filtering)
        fires = Repo.all(Fire)
        assert length(fires) == 3
      end
    end

    test "handles empty CSV response" do
      with_mocks([
        {HTTPoison, [],
         [
           get: fn _url, _headers, _opts ->
             {:ok, %{status_code: 200, body: ""}}
           end
         ]}
      ]) do
        assert :ok = perform_job(FireFetch, %{"days_back" => 1})

        # No fires should be created
        assert Repo.aggregate(Fire, :count) == 0
      end
    end

    test "handles HTTP errors" do
      with_mocks([
        {HTTPoison, [],
         [
           get: fn _url, _headers, _opts ->
             {:ok, %{status_code: 500, body: "Internal Server Error"}}
           end
         ]}
      ]) do
        # All satellites fail, so job should fail
        assert {:error, _reason} = perform_job(FireFetch, %{"days_back" => 1})
      end
    end

    test "handles network errors" do
      with_mocks([
        {HTTPoison, [],
         [
           get: fn _url, _headers, _opts ->
             {:error, %HTTPoison.Error{reason: :timeout}}
           end
         ]}
      ]) do
        # All satellites fail, so job should fail
        assert {:error, _reason} = perform_job(FireFetch, %{"days_back" => 1})
      end
    end

    test "partial failure - some satellites succeed" do
      with_mocks([
        {HTTPoison, [],
         [
           get: fn url, _headers, _opts ->
             if String.contains?(url, "VIIRS_SNPP_NRT") do
               {:ok, %{status_code: 200, body: @high_quality_csv}}
             else
               {:error, %HTTPoison.Error{reason: :timeout}}
             end
           end
         ]}
      ]) do
        # Should succeed since at least one satellite works
        assert :ok = perform_job(FireFetch, %{"days_back" => 1})

        # Verify fires were created from successful satellite
        fires = Repo.all(Fire)
        assert length(fires) == 2
      end
    end
  end

  describe "enqueue_now/1" do
    test "enqueues a FireFetch job with default days_back" do
      {:ok, job} = FireFetch.enqueue_now()

      assert job.args == %{"days_back" => 1}
      assert job.worker == "App.Workers.FireFetch"
      assert job.queue == "default"
    end

    test "enqueues a FireFetch job with custom days_back" do
      {:ok, job} = FireFetch.enqueue_now(3)

      assert job.args == %{"days_back" => 3}
    end
  end

  describe "api_key_configured?/0" do
    test "returns false for default placeholder key" do
      # Temporarily unset the API key for this test
      original_key = System.get_env("NASA_FIRMS_API_KEY")
      System.delete_env("NASA_FIRMS_API_KEY")

      refute FireFetch.api_key_configured?()

      # Restore the original key
      if original_key do
        System.put_env("NASA_FIRMS_API_KEY", original_key)
      end
    end

    test "returns true for valid API key" do
      # Temporarily set a valid-looking API key
      System.put_env("NASA_FIRMS_API_KEY", "valid_key_12345678901234567890")

      assert FireFetch.api_key_configured?()

      # Clean up - restore original or remove
      original_key = System.get_env("NASA_FIRMS_API_KEY")

      if original_key == "valid_key_12345678901234567890" do
        System.delete_env("NASA_FIRMS_API_KEY")
      end
    end
  end
end
