defmodule Trekmap.Application do
  use Application

  def start(_type, _args) do
    children = [
      Trekmap.SessionManager,
      Trekmap.Bots.Guardian,
      Trekmap.Bots.GalaxyScanner,
      Plug.Cowboy.child_spec(scheme: :http, plug: Trekmap.Router, options: [port: port()])
    ]

    opts = [strategy: :one_for_all, name: Trekmap.Application.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp port do
    if port = System.get_env("PORT") do
      String.to_integer(port)
    else
      4000
    end
  end
end
