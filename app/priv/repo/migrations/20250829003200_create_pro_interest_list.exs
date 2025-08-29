defmodule App.Repo.Migrations.CreateProInterestList do
  use Ecto.Migration

  def change do
    create table(:pro_interest) do
      add :email, :string, null: false
      # "pro" or "business" 
      add :plan_type, :string, null: false, default: "pro"
      # optional message from user
      add :message, :text
      # which page they signed up from
      add :source_page, :string
      # browser info for analytics
      add :user_agent, :string
      # for deduplication
      add :ip_address, :string
      add :verified, :boolean, default: false
      # when we launch, mark as notified
      add :notified, :boolean, default: false

      timestamps()
    end

    create unique_index(:pro_interest, [:email, :plan_type])
    create index(:pro_interest, [:email])
    create index(:pro_interest, [:plan_type])
    create index(:pro_interest, [:inserted_at])
  end
end
