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
end