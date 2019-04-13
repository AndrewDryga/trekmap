defmodule Trekmap.Bots.Admiral do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[Admiral] Everything is under control")
    current_mission_plan = Trekmap.Bots.Admiral.MissionPlans.multitasking_mission_plan()
    # current_mission_plan = Trekmap.Bots.Admiral.MissionPlans.war_mission_plan()
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()

    state = %{
      current_mission_plan: current_mission_plan,
      fleet_reports: %{},
      raid_report: %{},
      station_report: %{
        under_attack?: false,
        shield_enabled?: false,
        fleet_damage_ratio: 0
      },
      session: session
    }

    {:ok, state, 0}
  end

  def get_mission_plan do
    try do
      GenServer.call(__MODULE__, :get_mission_plan)
    catch
      :exit, _ -> %{}
    end
  end

  def set_mission_plan(mission_plan) do
    Enum.flat_map(mission_plan, fn
      {"mission_observer", _opts} ->
        []

      {_dock_id, {_strategy, ship_opts, _strategy_opts}} ->
        Keyword.get(ship_opts, :crew, [])
    end)
    |> Enum.reject(&(&1 == -1))
    |> Enum.group_by(& &1)
    |> Enum.each(fn {crew_id, entries} ->
      if length(entries) > 1 do
        raise "Duplicate crew member #{crew_id} detected in plan #{inspect(mission_plan)}"
      end
    end)

    GenServer.call(__MODULE__, {:set_mission_plan, mission_plan}, 30_000)
  end

  def get_fleet_reports do
    GenServer.call(__MODULE__, :get_fleet_reports)
  end

  def update_fleet_report(report) do
    try do
      GenServer.cast(__MODULE__, {:update_fleet_report, report})
    catch
      :exit, _ -> :ok
    end
  end

  def get_station_report do
    GenServer.call(__MODULE__, :get_station_report)
  end

  def update_station_report(report) do
    try do
      GenServer.cast(__MODULE__, {:update_station_report, report})
    catch
      :exit, _ -> :ok
    end
  end

  def get_raid_report do
    GenServer.call(__MODULE__, :get_raid_report)
  end

  def update_raid_report(report) do
    try do
      GenServer.cast(__MODULE__, {:update_raid_report, report})
    catch
      :exit, _ -> :ok
    end
  end

  def handle_cast({:update_fleet_report, report}, %{fleet_reports: fleet_reports} = state) do
    report = Map.put(report, :updated_at, DateTime.utc_now())
    fleet_reports = Map.put(fleet_reports, report.fleet_id, report)
    {:noreply, %{state | fleet_reports: fleet_reports}}
  end

  def handle_cast({:update_station_report, station_report}, state) do
    {:noreply, %{state | station_report: station_report}}
  end

  def handle_cast({:update_raid_report, raid_report}, %{raid_report: current_raid_report} = state) do
    raid_report =
      Enum.reduce(raid_report, current_raid_report, fn
        {_key, nil}, raid_report -> raid_report
        {key, value}, raid_report -> Map.put(raid_report, key, value)
      end)

    {:noreply, %{state | raid_report: raid_report}}
  end

  def handle_call(:get_mission_plan, _from, state) do
    %{current_mission_plan: current_mission_plan} = state
    {:reply, current_mission_plan, state}
  end

  def handle_call({:set_mission_plan, mission_plan}, _from, state) do
    Trekmap.Bots.FleetCommander.apply_mission_plan(mission_plan)
    {:reply, :ok, %{state | current_mission_plan: mission_plan}}
  end

  def handle_call(:get_fleet_reports, _from, %{session: session} = state) do
    %{fleet_reports: fleet_reports} = state

    fleet_reports =
      fleet_reports
      |> Map.values()
      |> Enum.map(fn fleet_report ->
        system = Trekmap.Me.get_system(fleet_report.fleet.system_id, session)
        Map.put(fleet_report, :system, system)
      end)

    {:reply, fleet_reports, state}
  end

  def handle_call(:get_station_report, _from, state) do
    %{station_report: station_report, session: session} = state
    shield_enabled? = Trekmap.Me.shield_enabled?(session)
    station_report = Map.put(station_report, :shield_enabled?, shield_enabled?)
    {:reply, station_report, %{state | station_report: station_report}}
  end

  def handle_call(:get_raid_report, _from, %{raid_report: raid_report} = state) do
    {:reply, raid_report, state}
  end

  def handle_info(:timeout, %{current_mission_plan: current_mission_plan} = state) do
    Trekmap.Bots.FleetCommander.apply_mission_plan(current_mission_plan)
    {:noreply, state}
  end
end
