defmodule App.Config do
  @moduledoc """
  Configuration helper module for FirePing application settings.
  """

  @doc """
  Get the incident cleanup threshold in hours.

  This determines how long an incident can be inactive before being marked as ended.
  """
  def incident_cleanup_threshold_hours do
    Application.get_env(:app, :incident_cleanup_threshold_hours, 24)
  end

  @doc """
  Get the fire clustering expiry window in hours.

  This determines how far back to look for existing incidents when clustering new fires.
  """
  def fire_clustering_expiry_hours do
    Application.get_env(:app, :fire_clustering_expiry_hours, 24)
  end

  @doc """
  Get the incident deletion threshold in days.

  This determines how old an ended incident must be before it gets deleted.
  """
  def incident_deletion_threshold_days do
    Application.get_env(:app, :incident_deletion_threshold_days, 3)
  end

  @doc """
  Get the default fire clustering distance in meters.

  This determines the maximum distance between fires to be considered part of the same incident.
  """
  def fire_clustering_distance_meters do
    Application.get_env(:app, :fire_clustering_distance_meters, 5000)
  end
end
