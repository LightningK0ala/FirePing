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

    if failed_count == length(devices) and failed_count > 0 do
      [failed_result | _] = failed_results
      {:failed, reason} = failed_result
      Notification.mark_as_failed(notification, reason)
    end

    {:ok, %{sent: sent_count, failed: failed_count}}
  end

  defp list_active_notification_devices(user_id) do
    NotificationDevice
    |> where([d], d.user_id == ^user_id and d.active == true)
    |> Repo.all()
  end

  defp send_to_device(notification, %NotificationDevice{channel: "web_push"} = device) do
    App.WebPush.send_notification(notification, device)
  end

  defp send_to_device(_notification, %NotificationDevice{channel: channel}) do
    # For now, other channels are not implemented
    {:error, "#{channel} channel not yet implemented"}
  end
end
