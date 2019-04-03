defmodule Trekmap.Bots.SupervisorChild do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Trekmap.Bots.SessionManager,
      Trekmap.Bots.FleetCommander,
      Trekmap.Bots.Admiral,
      Trekmap.Bots.Guardian,
      # Trekmap.Bots.GalaxyScanner,
      Trekmap.Bots.Helper,
      Trekmap.Bots.ChestCollector
      # Trekmap.Bots.HiveScanner,
      # Trekmap.Bots.NameChanger
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
