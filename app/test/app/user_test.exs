defmodule App.UserTest do
  use App.DataCase

  alias App.User

  describe "changeset/2" do
    test "valid changeset with email" do
      changeset = User.changeset(%User{}, %{email: "test@example.com"})
      assert changeset.valid?
    end

    test "invalid changeset without email" do
      changeset = User.changeset(%User{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "invalid changeset with invalid email format" do
      changeset = User.changeset(%User{}, %{email: "invalid-email"})
      refute changeset.valid?
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "invalid changeset with email containing spaces" do
      changeset = User.changeset(%User{}, %{email: "test @example.com"})
      refute changeset.valid?
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "invalid changeset with email too long" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      changeset = User.changeset(%User{}, %{email: long_email})
      refute changeset.valid?
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end
  end

  describe "generate_otp_changeset/1" do
    test "generates OTP token and expiry" do
      user = %User{email: "test@example.com"}
      changeset = User.generate_otp_changeset(user)

      assert changeset.changes.otp_token
      assert String.length(changeset.changes.otp_token) == 6
      assert String.match?(changeset.changes.otp_token, ~r/^\d{6}$/)
      assert changeset.changes.otp_expires_at
      assert DateTime.compare(changeset.changes.otp_expires_at, DateTime.utc_now()) == :gt
    end
  end

  describe "verify_otp_changeset/2" do
    test "valid OTP verification" do
      user = %User{
        email: "test@example.com",
        otp_token: "123456",
        otp_expires_at:
          DateTime.utc_now() |> DateTime.add(10, :minute) |> DateTime.truncate(:second)
      }

      changeset = User.verify_otp_changeset(user, "123456")
      assert changeset.valid?
      assert changeset.changes.otp_token == nil
      assert changeset.changes.otp_expires_at == nil
      assert changeset.changes.verified_at
    end

    test "invalid OTP token" do
      user = %User{
        email: "test@example.com",
        otp_token: "123456",
        otp_expires_at:
          DateTime.utc_now() |> DateTime.add(10, :minute) |> DateTime.truncate(:second)
      }

      changeset = User.verify_otp_changeset(user, "wrong")
      refute changeset.valid?
      assert "invalid or expired" in errors_on(changeset).otp_token
    end

    test "expired OTP token" do
      user = %User{
        email: "test@example.com",
        otp_token: "123456",
        otp_expires_at:
          DateTime.utc_now() |> DateTime.add(-10, :minute) |> DateTime.truncate(:second)
      }

      changeset = User.verify_otp_changeset(user, "123456")
      refute changeset.valid?
      assert "invalid or expired" in errors_on(changeset).otp_token
    end
  end

  describe "verified?/1" do
    test "returns true for verified user" do
      user = %User{verified_at: DateTime.utc_now() |> DateTime.truncate(:second)}
      assert User.verified?(user)
    end

    test "returns false for unverified user" do
      user = %User{verified_at: nil}
      refute User.verified?(user)
    end
  end

  describe "admin field" do
    test "defaults to false for new user" do
      changeset = User.changeset(%User{}, %{email: "test@example.com"})
      user = Ecto.Changeset.apply_changes(changeset)
      refute user.admin
    end

    test "can be set to true" do
      user = %User{email: "admin@example.com", admin: true}
      assert user.admin
    end

    test "persists admin flag in database" do
      {:ok, user} = User.create_or_get_user("admin@example.com")
      user = App.Repo.update!(Ecto.Changeset.change(user, admin: true))

      # Reload from database
      reloaded_user = App.Repo.get!(User, user.id)
      assert reloaded_user.admin
    end
  end

  describe "create_or_get_user/1" do
    test "creates new user if email doesn't exist" do
      {:ok, user} = User.create_or_get_user("new@example.com")
      assert user.email == "new@example.com"
      assert user.id
    end

    test "returns existing user if email exists" do
      existing_user = insert(:user, email: "existing@example.com")
      {:ok, user} = User.create_or_get_user("existing@example.com")
      assert user.id == existing_user.id
    end

    test "returns error for invalid email" do
      {:error, changeset} = User.create_or_get_user("invalid-email")
      refute changeset.valid?
    end
  end

  describe "authenticate_user/2" do
    test "successfully authenticates user with valid OTP" do
      _user =
        insert(:user,
          email: "test@example.com",
          otp_token: "123456",
          otp_expires_at:
            DateTime.utc_now() |> DateTime.add(10, :minute) |> DateTime.truncate(:second)
        )

      {:ok, authenticated_user} = User.authenticate_user("test@example.com", "123456")
      assert authenticated_user.verified_at
      assert authenticated_user.otp_token == nil
    end

    test "returns error for non-existent user" do
      {:error, :user_not_found} = User.authenticate_user("nonexistent@example.com", "123456")
    end

    test "returns error for invalid OTP" do
      insert(:user,
        email: "test@example.com",
        otp_token: "123456",
        otp_expires_at:
          DateTime.utc_now() |> DateTime.add(10, :minute) |> DateTime.truncate(:second)
      )

      {:error, changeset} = User.authenticate_user("test@example.com", "wrong")
      refute changeset.valid?
    end
  end
end
