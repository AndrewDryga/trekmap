defmodule Trekmap.Application do
  use Application

  def start(_type, _args) do
    children = [
      Trekmap.SessionManager,
      Trekmap.Bots.Guardian,
      Trekmap.Bots.GalaxyScanner
    ]

    opts = [strategy: :one_for_all, name: Trekmap.Application.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
