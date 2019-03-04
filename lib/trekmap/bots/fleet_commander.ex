defmodule Trekmap.Bots.FleetCommander do
  use DynamicSupervisor

  @fleet [
    Trekmap.Me.Fleet.jellyfish_fleet_id(),
    Trekmap.Me.Fleet.northstar_fleet_id(),
    Trekmap.Me.Fleet.kehra_fleet_id()
  ]

  @default_assignment {Trekmap.Bots.FleetCommander.Strategies.StationDefender, []}

  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def apply_mission_plan(mission_plan) do
    :ok = stop_all_missions()

    Enum.each(@fleet, fn fleet_id ->
      {strategy, strategy_config} = Map.get(mission_plan, fleet_id, @default_assignment)
      child = {Trekmap.Bots.FleetCommander.StartshipActor, {fleet_id, strategy, strategy_config}}
      DynamicSupervisor.start_child(__MODULE__, child)
    end)
  end

  defp stop_all_missions do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.each(fn {_fleet_id, pid, :worker, _module} ->
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end)
  end

  def pause_all_missions(timeout \\ nil) do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.each(fn {_fleet_id, pid, :worker, _module} ->
      :ok = Trekmap.Bots.FleetCommander.StartshipActor.pause_mission(pid, timeout)
    end)
  end

  def unpause_all_missions do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.each(fn {_fleet_id, pid, :worker, _module} ->
      :ok = Trekmap.Bots.FleetCommander.StartshipActor.unpause_mission(pid)
    end)
  end

  def continue_all_missions do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.each(fn {_fleet_id, pid, :worker, _module} ->
      :ok = Trekmap.Bots.FleetCommander.StartshipActor.continue_mission(pid)
    end)
  end

  def list_fleet_ids_on_active_missions do
    (Trekmap.Bots.Admiral.get_mission_plan() || %{})
    |> Map.keys()
  end
end
