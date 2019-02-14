defmodule Trekmap.Application do
  use Application

  def start(_type, _args) do
    children = [
      Trekmap.Bots.Supervisor,
      Trekmap.Bots,
      Plug.Cowboy.child_spec(scheme: :http, plug: Trekmap.Router, options: [port: port()]),
      {Cachex, :airdb_cache}
    ]

    opts = [strategy: :one_for_all, name: Trekmap.Application.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    {:ok, _bots_pid} = Trekmap.Bots.Supervisor.start_bots()

    {:ok, pid}
  end

  defp port do
    if port = System.get_env("PORT") do
      String.to_integer(port)
    else
      4000
    end
  end
end
