defmodule Trekmap.Bots.Admiral do
  use GenServer
  require Logger

  @fraction_klingon 4_153_667_145

  @other_time_officers [
    1_622_062_016,
    1_525_867_544,
    194_631_754,
    1_853_520_303,
    4_066_988_596,
    4_150_311_506,
    668_528_267,
    2_865_735_742,
    -1,
    -1
  ]

  @enterprise_crew_officers [
    2_520_801_863,
    282_462_507,
    766_809_588,
    3_155_244_352,
    3_923_643_019,
    2_765_885_322,
    250_991_574,
    -1,
    -1,
    -1
  ]

  @glory_in_kill_officers [
    3_394_864_658,
    2_517_597_941,
    680_147_223,
    339_936_167,
    98_548_875,
    2_235_857_051,
    2_601_201_375,
    176_044_746,
    -1,
    -1
  ]

  @raid_transport_officers [
    755_079_845,
    3_816_036_121,
    3_156_736_320,
    339_936_167,
    98_548_875,
    2_235_857_051,
    2_601_201_375,
    176_044_746,
    -1,
    -1
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[Admiral] Everything is under control")
    current_mission_plan = g2_g3_miner_hunting_and_hive_defence_mission_plan()
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

  def g2_miner_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.drydock1_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "Vahklas",
          crew: @other_time_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 2_000,
          skip_nearest_system?: false,
          max_warp_distance: 23
        ]
      },
      Trekmap.Me.Fleet.drydock2_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "North Star",
          crew: @enterprise_crew_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 50_000,
          skip_nearest_system?: false,
          max_warp_distance: 29
        ]
      },
      Trekmap.Me.Fleet.drydock3_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "Kehra",
          crew: @glory_in_kill_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 2_000,
          skip_nearest_system?: true,
          max_warp_distance: 21
        ]
      }
    }
  end

  def g3_mining_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.drydock1_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "Vahklas",
          crew: @other_time_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 30_000,
          skip_nearest_system?: false,
          max_warp_distance: 23
        ]
      },
      Trekmap.Me.Fleet.drydock2_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "North Star",
          crew: @enterprise_crew_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 50_000,
          skip_nearest_system?: false,
          max_warp_distance: 29
        ]
      },
      Trekmap.Me.Fleet.drydock3_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "Kehra",
          crew: @glory_in_kill_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 30_000,
          skip_nearest_system?: true,
          max_warp_distance: 21
        ]
      }
    }
  end

  def g2_miners_and_klingon_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.drydock1_id() => {
        Trekmap.Bots.FleetCommander.Strategies.FractionHunter,
        [
          ship: "Vahklas",
          crew: @other_time_officers
        ],
        [
          fraction_ids: [@fraction_klingon],
          patrol_systems:
            [
              1_984_126_753,
              355_503_878,
              1_731_519_518,
              975_691_590,
              1_691_252_927,
              1_744_652_289,
              846_029_245,
              1_780_286_771,
              1_358_992_189,
              1_057_703_933,
              369_364_082,
              399_469_984,
              893_618_014,
              186_798_495,
              1_090_722_450,
              265_649_208,
              395_344_716,
              1_735_899_624,
              1_244_441_919,
              1_926_261_734,
              430_080_081,
              1_490_400_924,
              2_075_950_099,
              1_694_524_999,
              1_756_718_205,
              776_886_360,
              1_295_669_729,
              1_759_717_590,
              1_101_989_561,
              1_862_365_964,
              1_660_792_724,
              1_245_655_537,
              1_566_236_961,
              477_613_271
            ]
            |> Enum.uniq(),
          min_targets_in_system: 1,
          min_target_level: 27,
          max_target_level: 30,
          skip_nearest_system?: false,
          max_warp_distance: 23
        ]
      },
      Trekmap.Me.Fleet.drydock2_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "North Star",
          crew: @enterprise_crew_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 100_000,
          skip_nearest_system?: false,
          max_warp_distance: 29
        ]
      },
      Trekmap.Me.Fleet.drydock3_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "Kehra",
          crew: @glory_in_kill_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 2_000,
          skip_nearest_system?: true,
          max_warp_distance: 21
        ]
      }
    }
  end

  def g2_g3_miner_hunting_and_hive_defence_mission_plan do
    %{
      Trekmap.Me.Fleet.drydock1_id() => {
        Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
        [
          ship: "Vahklas",
          crew: @other_time_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          min_target_bounty_score: 50_000,
          skip_nearest_system?: false,
          max_warp_distance: 23
        ]
      },
      Trekmap.Me.Fleet.drydock2_id() => {
        Trekmap.Bots.FleetCommander.Strategies.HiveDefender,
        [
          ship: "North Star",
          crew: @enterprise_crew_officers
        ],
        [
          min_target_level: 18,
          max_target_level: 33
        ]
      },
      Trekmap.Me.Fleet.drydock3_id() => {
        Trekmap.Bots.FleetCommander.Strategies.Punisher,
        [
          ship: "Kehra",
          crew: @glory_in_kill_officers
        ],
        [
          patrol_systems: Trekmap.Galaxy.list_system_ids_with_g2_g3_resources(),
          min_targets_in_system: 1,
          min_target_level: 18,
          max_target_level: 33,
          skip_nearest_system?: false,
          max_warp_distance: 21
        ]
      }
    }
  end

  def raid_mission_plan(target_user_id) do
    with {:ok, target_station} = Trekmap.Galaxy.System.Station.find_station(target_user_id) do
      %{
        Trekmap.Me.Fleet.drydock1_id() => {
          Trekmap.Bots.FleetCommander.Strategies.RaidLooter,
          [
            ship: "Envoy 1",
            crew: @other_time_officers
          ],
          [
            target_station: target_station
          ]
        },
        Trekmap.Me.Fleet.drydock2_id() => {
          Trekmap.Bots.FleetCommander.Strategies.RaidLeader,
          [
            ship: "North Star",
            crew: @enterprise_crew_officers
          ],
          [
            target_station: target_station
          ]
        },
        Trekmap.Me.Fleet.drydock3_id() => {
          Trekmap.Bots.FleetCommander.Strategies.RaidLooter,
          [
            ship: "Envoy 2",
            crew: @raid_transport_officers
          ],
          [
            target_station: target_station
          ]
        },
        "mission_observer" =>
          {Trekmap.Bots.FleetCommander.Observers.RaidObserver,
           [
             target_station: target_station
           ]}
      }
    end
  end

  def raid_mission_plan do
    g2_g3_miner_hunting_and_hive_defence_mission_plan()
    |> Map.put("mission_observer", {Trekmap.Bots.FleetCommander.Observers.RaidObserver, []})
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
