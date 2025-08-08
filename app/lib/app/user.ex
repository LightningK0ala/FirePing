defmodule App.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :otp_token, :string
    field :otp_expires_at, :utc_datetime
    field :verified_at, :utc_datetime
    field :admin, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_email()
    |> unique_constraint(:email)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
  end

  def generate_otp_changeset(user) do
    otp_token = generate_otp_token()
    expires_at = DateTime.utc_now() |> DateTime.add(15, :minute) |> DateTime.truncate(:second)
    
    user
    |> change(%{otp_token: otp_token, otp_expires_at: expires_at})
  end

  def verify_otp_changeset(user, token) do
    case valid_otp?(user, token) do
      true -> 
        user
        |> change(%{otp_token: nil, otp_expires_at: nil, verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})
      false -> 
        user
        |> change()
        |> add_error(:otp_token, "invalid or expired")
    end
  end

  def verified?(user), do: !is_nil(user.verified_at)

  def create_or_get_user(email) do
    case App.Repo.get_by(__MODULE__, email: email) do
      nil -> 
        %__MODULE__{}
        |> changeset(%{email: email})
        |> App.Repo.insert()
      user -> 
        {:ok, user}
    end
  end

  def authenticate_user(email, otp_token) do
    case App.Repo.get_by(__MODULE__, email: email) do
      nil -> 
        {:error, :user_not_found}
      user -> 
        changeset = verify_otp_changeset(user, otp_token)
        if changeset.valid? do
          App.Repo.update(changeset)
        else
          {:error, changeset}
        end
    end
  end

  defp valid_otp?(user, token) do
    user.otp_token == token and
    !is_nil(user.otp_expires_at) and
    DateTime.compare(DateTime.utc_now(), user.otp_expires_at) == :lt
  end

  defp generate_otp_token do
    100_000 + :rand.uniform(899_999) |> Integer.to_string()
  end
end
