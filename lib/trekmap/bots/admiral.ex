defmodule Trekmap.Bots.Admiral do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[Admiral] Everything is under control")
    current_mission_plan = passive_mining_hunting_mission_plan()
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()

    state = %{
      current_mission_plan: current_mission_plan,
      fleet_reports: %{},
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

  def agressive_mining_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.jellyfish_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 5,
          min_target_level: 16,
          max_target_level: 26,
          min_target_bounty_score: 1800,
          skip_nearest_system?: false
        ]
      },
      Trekmap.Me.Fleet.northstar_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 16,
          max_target_level: 26,
          min_target_bounty_score: 300_000,
          skip_nearest_system?: false
        ]
      },
      Trekmap.Me.Fleet.kehra_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 2,
          min_target_level: 16,
          max_target_level: 26,
          min_target_bounty_score: 1600,
          skip_nearest_system?: true
        ]
      }
    }
  end

  def passive_mining_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.kehra_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 2,
          min_target_level: 16,
          max_target_level: 26,
          min_target_bounty_score: 1900,
          skip_nearest_system?: false
        ]
      },
      Trekmap.Me.Fleet.northstar_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g3_resources(),
          min_targets_in_system: 2,
          min_target_level: 16,
          max_target_level: 26,
          min_target_bounty_score: 150_000,
          skip_nearest_system?: false
        ]
      }
    }
  end

  def handle_cast({:update_fleet_report, report}, %{fleet_reports: fleet_reports} = state) do
    fleet_reports = Map.put(fleet_reports, report.fleet_id, report)
    {:noreply, %{state | fleet_reports: fleet_reports}}
  end

  def handle_cast({:update_station_report, station_report}, state) do
    {:noreply, %{state | station_report: station_report}}
  end

  def handle_call(:get_mission_plan, _from, state) do
    %{current_mission_plan: current_mission_plan} = state
    {:reply, current_mission_plan, state}
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

  def handle_info(:timeout, %{current_mission_plan: current_mission_plan} = state) do
    Trekmap.Bots.FleetCommander.apply_mission_plan(current_mission_plan)
    {:noreply, state}
  end
end
