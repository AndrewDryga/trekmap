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
      Trekmap.Bots.FleetCommander2,
      Trekmap.Bots.FractionHunter,
      Trekmap.Bots.Guardian,
      Trekmap.Bots.GalaxyScanner
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
