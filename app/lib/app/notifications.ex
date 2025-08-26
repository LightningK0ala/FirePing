defmodule App.Notifications do
  @moduledoc """
  The Notifications context.
  """

  import Ecto.Query, warn: false
  alias App.Repo

  alias App.{Notification, NotificationDevice}

  ## Notification Devices

  @doc """
  Returns the list of notification devices for a user.

  ## Examples

      iex> list_notification_devices(user_id)
      [%NotificationDevice{}, ...]

  """
  def list_notification_devices(user_id) do
    NotificationDevice
    |> where([d], d.user_id == ^user_id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single notification_device.

  Raises `Ecto.NoResultsError` if the NotificationDevice does not exist.

  ## Examples

      iex> get_notification_device!(id)
      %NotificationDevice{}

      iex> get_notification_device!(bad_id)
      ** (Ecto.NoResultsError)

  """
  def get_notification_device!(id), do: Repo.get!(NotificationDevice, id)

  @doc """
  Gets a single notification_device for a specific user.
  Returns nil if not found or doesn't belong to user.

  ## Examples

      iex> get_user_notification_device(user_id, device_id)
      %NotificationDevice{}

      iex> get_user_notification_device(user_id, bad_id)
      nil

  """
  def get_user_notification_device(user_id, device_id) do
    NotificationDevice
    |> where([d], d.user_id == ^user_id and d.id == ^device_id)
    |> Repo.one()
  end

  @doc """
  Creates a notification_device.

  ## Examples

      iex> create_notification_device(%{field: value})
      {:ok, %NotificationDevice{}}

      iex> create_notification_device(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification_device(attrs \\ %{}) do
    %NotificationDevice{}
    |> NotificationDevice.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification_device.

  ## Examples

      iex> update_notification_device(notification_device, %{field: new_value})
      {:ok, %NotificationDevice{}}

      iex> update_notification_device(notification_device, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_notification_device(%NotificationDevice{} = notification_device, attrs) do
    notification_device
    |> NotificationDevice.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a notification_device.

  ## Examples

      iex> delete_notification_device(notification_device)
      {:ok, %NotificationDevice{}}

      iex> delete_notification_device(notification_device)
      {:error, %Ecto.Changeset{}}

  """
  def delete_notification_device(%NotificationDevice{} = notification_device) do
    Repo.delete(notification_device)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking notification_device changes.

  ## Examples

      iex> change_notification_device(notification_device)
      %Ecto.Changeset{data: %NotificationDevice{}}

  """
  def change_notification_device(%NotificationDevice{} = notification_device, attrs \\ %{}) do
    NotificationDevice.changeset(notification_device, attrs)
  end

  ## Notifications

  @doc """
  Returns the list of notifications for a user.

  ## Examples

      iex> list_notifications(user_id)
      [%Notification{}, ...]

  """
  def list_notifications(user_id, limit \\ 50) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> preload([:fire_incident])
    |> Repo.all()
  end

  @doc """
  Gets a single notification.

  Raises `Ecto.NoResultsError` if the Notification does not exist.

  ## Examples

      iex> get_notification!(id)
      %Notification{}

      iex> get_notification!(bad_id)
      ** (Ecto.NoResultsError)

  """
  def get_notification!(id), do: Repo.get!(Notification, id)

  @doc """
  Creates a notification.

  ## Examples

      iex> create_notification(%{field: value})
      {:ok, %Notification{}}

      iex> create_notification(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification(attrs \\ %{}) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, notification} ->
        # Broadcast event so subscribers can update
        Phoenix.PubSub.broadcast(
          App.PubSub,
          "notifications:#{notification.user_id}",
          {:notification_created, notification}
        )

        {:ok, notification}

      error ->
        error
    end
  end

  @doc """
  Creates a test notification for a user.

  ## Examples

      iex> create_test_notification(user_id)
      {:ok, %Notification{}}

  """
  def create_test_notification(user_id) do
    create_notification(%{
      user_id: user_id,
      title: "Test Notification",
      body: "This is a test notification to verify your device is working correctly.",
      type: "test"
    })
  end

  @doc """
  Sends a notification to all active devices for a user.

  ## Examples

      iex> send_notification(notification)
      {:ok, %{sent: 2, failed: 0}}

  """
  def send_notification(%Notification{} = notification) do
    devices = list_active_notification_devices(notification.user_id)

    results =
      Enum.map(devices, fn device ->
        case send_to_device(notification, device) do
          :ok ->
            NotificationDevice.update_last_used(device)
            :sent

          {:error, reason} ->
            {:failed, reason}
        end
      end)

    sent_count = Enum.count(results, &(&1 == :sent))
    failed_results = Enum.filter(results, &match?({:failed, _}, &1))
    failed_count = length(failed_results)

    if sent_count > 0 do
      Notification.mark_as_sent(notification)
    end

    cond do
      # All devices failed - mark notification as failed and return error
      failed_count == length(devices) and failed_count > 0 ->
        [failed_result | _] = failed_results
        {:failed, reason} = failed_result
        Notification.mark_as_failed(notification, reason)
        {:error, reason}

      # No devices to send to
      length(devices) == 0 ->
        {:error, "No active notification devices found for user"}

      # Some or all devices succeeded
      true ->
        {:ok, %{sent: sent_count, failed: failed_count}}
    end
  end

  @doc """
  Sends a test notification to a specific device only.
  Creates only the device notification (no original notification).

  ## Examples

      iex> send_test_notification_to_device(device_id, attrs)
      {:ok, %{sent: 1, failed: 0}}

  """
  def send_test_notification_to_device(device_id, attrs) do
    case get_user_notification_device(attrs.user_id, device_id) do
      nil ->
        {:error, "Device not found or does not belong to user"}

      device ->
        # Create device-specific notification data
        device_data =
          Map.merge(attrs.data || %{}, %{
            "target_device_id" => device.id,
            "target_device_name" => device.name,
            "target_device_channel" => device.channel,
            "is_test_notification" => true
          })

        # Add webhook URL if it's a webhook device
        device_data =
          if device.channel == "webhook" do
            Map.merge(device_data, %{
              "webhook_url" => device.config["url"],
              "webhook_attempted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            })
          else
            device_data
          end

        # Create the device-specific notification
        device_notification_attrs = %{
          user_id: attrs.user_id,
          fire_incident_id: attrs[:fire_incident_id],
          title: attrs.title,
          body: attrs.body,
          type: attrs.type,
          data: device_data
        }

        case create_notification(device_notification_attrs) do
          {:ok, device_notification} ->
            case send_to_device(device_notification, device) do
              :ok ->
                NotificationDevice.update_last_used(device)
                Notification.mark_as_sent(device_notification)
                {:ok, %{sent: 1, failed: 0}}

              {:error, reason} ->
                Notification.mark_as_failed(device_notification, reason)
                {:error, reason}
            end

          {:error, changeset} ->
            # Log the error for debugging
            require Logger
            Logger.error("Failed to create test notification", changeset: changeset)
            {:error, "Failed to create test notification"}
        end
    end
  end

  @doc """
  Sends notifications to all devices for a user without creating an original notification.
  Creates only device notifications (one per device).
  Used by the notification orchestrator for fire alerts.

  ## Examples

      iex> send_notifications_to_devices(attrs)
      {:ok, %{sent: 2, failed: 0}}

  """
  def send_notifications_to_devices(attrs) do
    devices = list_active_notification_devices(attrs.user_id)

    if length(devices) == 0 do
      {:error, "No active notification devices found for user"}
    else
      # Create and send notifications for each device
      results =
        Enum.map(devices, fn device ->
          create_and_send_device_notification(attrs, device)
        end)

      sent_count = Enum.count(results, &match?({:ok, _}, &1))
      failed_count = Enum.count(results, &match?({:error, _}, &1))

      {:ok, %{sent: sent_count, failed: failed_count}}
    end
  end

  defp create_and_send_device_notification(attrs, device) do
    # Create device-specific notification data
    device_data =
      Map.merge(attrs.data || %{}, %{
        "target_device_id" => device.id,
        "target_device_name" => device.name,
        "target_device_channel" => device.channel,
        "is_device_notification" => true
      })

    # Add webhook URL if it's a webhook device
    device_data =
      if device.channel == "webhook" do
        Map.merge(device_data, %{
          "webhook_url" => device.config["url"],
          "webhook_attempted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
      else
        device_data
      end

    # Create the device-specific notification
    device_notification_attrs = %{
      user_id: attrs.user_id,
      fire_incident_id: attrs.fire_incident_id,
      title: attrs.title,
      body: attrs.body,
      type: attrs.type,
      data: device_data
    }

    case create_notification(device_notification_attrs) do
      {:ok, device_notification} ->
        case send_to_device(device_notification, device) do
          :ok ->
            NotificationDevice.update_last_used(device)
            Notification.mark_as_sent(device_notification)
            {:ok, device_notification}

          {:error, reason} ->
            Notification.mark_as_failed(device_notification, reason)
            {:error, reason}
        end

      {:error, changeset} ->
        # Log the error for debugging
        require Logger
        Logger.error("Failed to create device notification", changeset: changeset)
        {:error, "Failed to create device notification"}
    end
  end

  defp list_active_notification_devices(user_id) do
    NotificationDevice
    |> where([d], d.user_id == ^user_id and d.active == true)
    |> Repo.all()
  end

  defp send_to_device(notification, %NotificationDevice{channel: "web_push"} = device) do
    App.WebPush.send_notification(notification, device)
  end

  defp send_to_device(notification, %NotificationDevice{channel: "webhook"} = device) do
    App.Webhook.send_notification(notification, device)
  end

  defp send_to_device(_notification, %NotificationDevice{channel: channel}) do
    # For now, other channels are not implemented
    {:error, "#{channel} channel not yet implemented"}
  end
end
