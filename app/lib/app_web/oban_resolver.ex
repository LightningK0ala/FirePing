defmodule AppWeb.ObanResolver do
  @behaviour Oban.Web.Resolver

  @impl true
  def format_job_meta(%Oban.Job{meta: meta}) do
    inspect(meta || %{}, pretty: true, limit: :infinity)
  end

  @impl true
  def format_job_args(%Oban.Job{args: args}) do
    Oban.Web.Resolver.format_job_args(%Oban.Job{args: args})
  end
end



