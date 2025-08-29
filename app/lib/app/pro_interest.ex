defmodule App.ProInterest do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pro_interest" do
    field :email, :string
    field :plan_type, :string, default: "pro"
    field :message, :string
    field :source_page, :string
    field :user_agent, :string
    field :ip_address, :string
    field :verified, :boolean, default: false
    field :notified, :boolean, default: false

    timestamps()
  end

  def changeset(pro_interest, attrs) do
    pro_interest
    |> cast(attrs, [:email, :plan_type, :message, :source_page, :user_agent, :ip_address])
    |> validate_required([:email, :plan_type])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_inclusion(:plan_type, ["pro", "business"])
    |> unique_constraint([:email, :plan_type],
      message: "You're already on the waitlist for this plan!"
    )
  end

  def create_interest(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> App.Repo.insert()
  end

  def get_by_email_and_plan(email, plan_type) do
    App.Repo.get_by(__MODULE__, email: email, plan_type: plan_type)
  end

  def count_by_plan(plan_type) do
    import Ecto.Query

    from(p in __MODULE__, where: p.plan_type == ^plan_type)
    |> App.Repo.aggregate(:count, :id)
  end

  def all_for_notification(plan_type) do
    import Ecto.Query

    from(p in __MODULE__,
      where: p.plan_type == ^plan_type and p.notified == false,
      order_by: [asc: p.inserted_at]
    )
    |> App.Repo.all()
  end
end
