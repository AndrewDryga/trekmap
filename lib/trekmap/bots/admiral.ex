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

  def set_mission_plan(mission_plan) do
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

  def agressive_mining_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.vakhlas_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 2,
          min_target_level: 17,
          max_target_level: 33,
          min_target_bounty_score: 70_000,
          skip_nearest_system?: false,
          max_warp_distance: 23
        ]
      },
      Trekmap.Me.Fleet.northstar_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 17,
          max_target_level: 33,
          min_target_bounty_score: 200_000,
          skip_nearest_system?: false,
          max_warp_distance: 29
        ]
      },
      Trekmap.Me.Fleet.kehra_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 2,
          min_target_level: 17,
          max_target_level: 33,
          min_target_bounty_score: 70_000,
          skip_nearest_system?: true,
          max_warp_distance: 21
        ]
      }
    }
  end

  def agressive_mining_and_fraction_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.vakhlas_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.FractionHunter,
        [
          exclude_fraction_ids: [-1],
          patrol_systems: [
            1_984_126_753,
            355_503_878,
            1_731_519_518,
            975_691_590,
            1_691_252_927,
            1_744_652_289,
            846_029_245,
            1_780_286_771,
            1_358_992_189
          ],
          min_targets_in_system: 1,
          min_target_level: 23,
          max_target_level: 28,
          skip_nearest_system?: false,
          max_warp_distance: 23
        ]
      },
      Trekmap.Me.Fleet.northstar_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 17,
          max_target_level: 33,
          min_target_bounty_score: 200_000,
          skip_nearest_system?: false,
          max_warp_distance: 29
        ]
      },
      Trekmap.Me.Fleet.kehra_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 2,
          min_target_level: 17,
          max_target_level: 33,
          min_target_bounty_score: 70_000,
          skip_nearest_system?: true,
          max_warp_distance: 21
        ]
      }
    }
  end

  def passive_mining_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.vakhlas_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 2,
          min_target_level: 17,
          max_target_level: 33,
          min_target_bounty_score: 50_000,
          skip_nearest_system?: false,
          max_warp_distance: 23
        ]
      },
      Trekmap.Me.Fleet.kehra_fleet_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 2,
          min_target_level: 17,
          max_target_level: 33,
          min_target_bounty_score: 70_000,
          skip_nearest_system?: false,
          max_warp_distance: 21
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

  def handle_info(:timeout, %{current_mission_plan: current_mission_plan} = state) do
    Trekmap.Bots.FleetCommander.apply_mission_plan(current_mission_plan)
    {:noreply, state}
  end
end
