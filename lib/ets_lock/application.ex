defmodule EtsLock.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    :ets.new(EtsLock.Locks, [
      :duplicate_bag,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    children = []
    opts = [strategy: :one_for_one, name: EtsLock.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
