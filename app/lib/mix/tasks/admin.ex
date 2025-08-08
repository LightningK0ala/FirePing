defmodule Mix.Tasks.Admin.Grant do
  @moduledoc "Grant admin privileges to user"
  use Mix.Task
  import Ecto.Query

  def run([email]) when is_binary(email) do
    Mix.Task.run("app.start")

    case App.User.create_or_get_user(email) do
      {:ok, user} ->
        case App.Repo.update(Ecto.Changeset.change(user, admin: true)) do
          {:ok, _user} ->
            Mix.shell().info("✅ Admin privileges granted to #{email}")

          {:error, changeset} ->
            Mix.shell().error("❌ Failed to grant admin privileges: #{inspect(changeset.errors)}")
        end

      {:error, changeset} ->
        Mix.shell().error(
          "❌ Invalid email or failed to create user: #{inspect(changeset.errors)}"
        )
    end
  end

  def run(_) do
    Mix.shell().info("Usage: mix admin.grant <email>")
  end
end

defmodule Mix.Tasks.Admin.Revoke do
  @moduledoc "Revoke admin privileges from user"
  use Mix.Task

  def run([email]) when is_binary(email) do
    Mix.Task.run("app.start")

    case App.Repo.get_by(App.User, email: email) do
      nil ->
        Mix.shell().error("❌ User #{email} not found")

      user ->
        case App.Repo.update(Ecto.Changeset.change(user, admin: false)) do
          {:ok, _user} ->
            Mix.shell().info("✅ Admin privileges revoked from #{email}")

          {:error, changeset} ->
            Mix.shell().error("❌ Failed to revoke admin privileges: #{inspect(changeset.errors)}")
        end
    end
  end

  def run(_) do
    Mix.shell().info("Usage: mix admin.revoke <email>")
  end
end

defmodule Mix.Tasks.Admin.List do
  @moduledoc "List all admin users"
  use Mix.Task
  import Ecto.Query

  def run(_args) do
    Mix.Task.run("app.start")

    admins =
      App.User
      |> where(admin: true)
      |> App.Repo.all()

    if Enum.empty?(admins) do
      Mix.shell().info("No admin users found")
    else
      Mix.shell().info("Admin users:")

      Enum.each(admins, fn user ->
        verified = if user.verified_at, do: "✓", else: "✗"
        Mix.shell().info("  #{verified} #{user.email} (#{user.id})")
      end)
    end
  end
end
