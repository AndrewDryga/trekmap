defmodule Trekmap.Application do
  use Application

  def start(_type, _args) do
    port = System.get_env("PORT") || 4000

    children = [
      Trekmap.SessionManager,
      Trekmap.Bots.Guardian,
      Trekmap.Bots.GalaxyScanner,
      Plug.Cowboy.child_spec(scheme: :http, plug: Trekmap.Router, options: [port: port])
    ]

    opts = [strategy: :one_for_all, name: Trekmap.Application.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
