defmodule Trekmap.Bots.Admiral.MissionPlans do
  @fraction_neutral_or_elite -1
  @fraction_klingon 4_153_667_145

  @klingon_elite_systems [395_344_716, 1_090_722_450]

  @pvp_target_level_opts [min_target_level: 20, max_target_level: 45]

  defp hunt_miners(ship_set, opts) do
    {max_warp_distance, ship_opts} = Keyword.pop(ship_set, :max_warp_distance)

    {
      Trekmap.Bots.FleetCommander.Strategies.MinerHunter,
      ship_opts,
      [max_warp_distance: max_warp_distance] ++ @pvp_target_level_opts ++ opts
    }
  end

  defp mine(ship_set, opts) do
    {max_warp_distance, ship_opts} = Keyword.pop(ship_set, :max_warp_distance)

    {
      Trekmap.Bots.FleetCommander.Strategies.Miner,
      ship_opts,
      [max_warp_distance: max_warp_distance] ++ @pvp_target_level_opts ++ opts
    }
  end

  defp defend_hive_or_station(ship_set, opts \\ []) do
    {max_warp_distance, ship_opts} = Keyword.pop(ship_set, :max_warp_distance)

    strategy_opts = [max_warp_distance: max_warp_distance] ++ @pvp_target_level_opts ++ opts

    with {:ok, session} <- Trekmap.Bots.SessionManager.fetch_session(),
         true <- session.home_system_id in session.hive_system_ids do
      {Trekmap.Bots.FleetCommander.Strategies.HiveDefender, ship_opts, strategy_opts}
    else
      _other ->
        {Trekmap.Bots.FleetCommander.Strategies.StationDefender, ship_opts, strategy_opts}
    end
  end

  defp defend_station(ship_set, opts \\ []) do
    {max_warp_distance, ship_opts} = Keyword.pop(ship_set, :max_warp_distance)

    strategy_opts = [max_warp_distance: max_warp_distance] ++ @pvp_target_level_opts ++ opts

    {Trekmap.Bots.FleetCommander.Strategies.StationDefender, ship_opts, strategy_opts}
  end

  defp hunt_maradeurs(ship_set, opts) do
    {max_warp_distance, ship_opts} = Keyword.pop(ship_set, :max_warp_distance)

    {
      Trekmap.Bots.FleetCommander.Strategies.FractionHunter,
      ship_opts,
      [max_warp_distance: max_warp_distance] ++ opts
    }
  end

  defp break_station(ship_set, opts) do
    {max_warp_distance, ship_opts} = Keyword.pop(ship_set, :max_warp_distance)

    {
      Trekmap.Bots.FleetCommander.Strategies.RaidLeader,
      ship_opts,
      [max_warp_distance: max_warp_distance] ++ @pvp_target_level_opts ++ opts
    }
  end

  defp loot_station(ship_set, opts) do
    {max_warp_distance, ship_opts} = Keyword.pop(ship_set, :max_warp_distance)

    {
      Trekmap.Bots.FleetCommander.Strategies.RaidLooter,
      ship_opts,
      [max_warp_distance: max_warp_distance] ++ @pvp_target_level_opts ++ opts
    }
  end

  defp block_enemy_station(ship_set, opts) do
    {max_warp_distance, ship_opts} = Keyword.pop(ship_set, :max_warp_distance)

    {Trekmap.Bots.FleetCommander.Strategies.Blockade, ship_opts,
     [max_warp_distance: max_warp_distance] ++ @pvp_target_level_opts ++ opts}
  end

  def war_mission_plan do
    overcargo_patrol_systems = Trekmap.Galaxy.fetch_hunting_system_ids!(grade: "***")

    %{
      Trekmap.Me.Fleet.drydock1_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.mayflower_set(),
          patrol_systems: overcargo_patrol_systems,
          min_targets_in_system: 1,
          min_target_bounty_score: 100_000
        ),
      Trekmap.Me.Fleet.drydock2_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.north_star_with_long_warp_set(),
          patrol_systems: overcargo_patrol_systems,
          min_targets_in_system: 1,
          min_target_bounty_score: 100_000
        ),
      Trekmap.Me.Fleet.drydock3_id() => defend_station(Trekmap.Me.Fleet.Setups.kumari_set()),
      Trekmap.Me.Fleet.drydock4_id() =>
        defend_station(Trekmap.Me.Fleet.Setups.vahklas_with_station_defence_set())
    }
  end

  def multitasking_mission_plan do
    # {:ok, faction_patrol_systems} = Trekmap.Galaxy.list_systems_for_faction("Klingon", 29)
    overcargo_patrol_systems = Trekmap.Galaxy.fetch_hunting_system_ids!(grade: "***")

    %{
      #   hunt_maradeurs(Trekmap.Me.Fleet.Setups.mayflower_set(),
      #     fraction_ids: [@fraction_klingon],
      #     patrol_systems: faction_patrol_systems,
      #     min_targets_in_system: 2,
      #     min_target_level: 29,
      #     max_target_level: 33
      #   ),
      Trekmap.Me.Fleet.drydock1_id() =>
        defend_hive_or_station(Trekmap.Me.Fleet.Setups.mayflower_set()),
      Trekmap.Me.Fleet.drydock2_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.north_star_set(),
          patrol_systems: overcargo_patrol_systems,
          min_targets_in_system: 1,
          min_target_bounty_score: 30_000
        ),
      Trekmap.Me.Fleet.drydock3_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.kumari_set(),
          patrol_systems: overcargo_patrol_systems,
          min_targets_in_system: 2,
          min_target_bounty_score: 50_000
        ),
      Trekmap.Me.Fleet.drydock4_id() =>
        defend_hive_or_station(Trekmap.Me.Fleet.Setups.vahklas_with_station_defence_set())
    }
  end

  def agressive_overcargo_hunting_mission_plan do
    patrol_systems = Trekmap.Galaxy.fetch_hunting_system_ids!(grade: "**")

    %{
      Trekmap.Me.Fleet.drydock1_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.mayflower_set(),
          patrol_systems: patrol_systems,
          min_targets_in_system: 2,
          min_target_bounty_score: 50_000
        ),
      Trekmap.Me.Fleet.drydock2_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.north_star_set(),
          patrol_systems: patrol_systems,
          min_targets_in_system: 1,
          min_target_bounty_score: 30_000
        ),
      Trekmap.Me.Fleet.drydock3_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.kumari_set(),
          patrol_systems: patrol_systems,
          min_targets_in_system: 1,
          min_target_bounty_score: 70_000
        ),
      Trekmap.Me.Fleet.drydock4_id() =>
        defend_hive_or_station(Trekmap.Me.Fleet.Setups.vahklas_with_station_defence_set())
    }
  end

  def overcargo_hunting_mission_plan do
    patrol_systems = Trekmap.Galaxy.fetch_hunting_system_ids!(grade: "***")

    %{
      Trekmap.Me.Fleet.drydock1_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.mayflower_set(),
          patrol_systems: patrol_systems,
          min_targets_in_system: 1,
          min_target_bounty_score: 50_000
        ),
      Trekmap.Me.Fleet.drydock2_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.north_star_set(),
          patrol_systems: patrol_systems,
          min_targets_in_system: 1,
          min_target_bounty_score: 50_000
        ),
      Trekmap.Me.Fleet.drydock3_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.kumari_set(),
          patrol_systems: patrol_systems,
          min_targets_in_system: 2,
          min_target_bounty_score: 50_000
        ),
      Trekmap.Me.Fleet.drydock4_id() =>
        defend_hive_or_station(Trekmap.Me.Fleet.Setups.vahklas_with_station_defence_set())
    }
  end

  def mining_mission_plan do
    patrol_systems = Trekmap.Galaxy.fetch_hunting_system_ids!(grade: "***")
    {:ok, mining_systems} = Trekmap.Galaxy.list_mining_systems("***")

    %{
      Trekmap.Me.Fleet.drydock1_id() =>
        hunt_miners(Trekmap.Me.Fleet.Setups.mayflower_set(),
          patrol_systems: patrol_systems,
          min_targets_in_system: 1,
          min_target_bounty_score: 50_000
        ),
      Trekmap.Me.Fleet.drydock2_id() =>
        mine(Trekmap.Me.Fleet.Setups.north_star_set(),
          patrol_systems: mining_systems,
          resource_name_filters: ["***"]
        ),
      Trekmap.Me.Fleet.drydock3_id() =>
        mine(Trekmap.Me.Fleet.Setups.horizon_set(),
          patrol_systems: mining_systems,
          resource_name_filters: ["***"]
        ),
      Trekmap.Me.Fleet.drydock4_id() =>
        defend_hive_or_station(Trekmap.Me.Fleet.Setups.vahklas_with_station_defence_set())
    }
  end

  def faction_hunting_mission_plan do
    {:ok, faction_patrol_systems} = Trekmap.Galaxy.list_systems_for_faction("Klingon", 29)

    %{
      Trekmap.Me.Fleet.drydock1_id() =>
        hunt_maradeurs(Trekmap.Me.Fleet.Setups.mayflower_set(),
          fraction_ids: [@fraction_klingon],
          patrol_systems: faction_patrol_systems,
          min_targets_in_system: 5,
          min_target_level: 29,
          max_target_level: 33
        ),
      Trekmap.Me.Fleet.drydock2_id() =>
        hunt_maradeurs(Trekmap.Me.Fleet.Setups.north_star_set(),
          fraction_ids: [@fraction_klingon],
          patrol_systems: faction_patrol_systems,
          min_targets_in_system: 5,
          min_target_level: 29,
          max_target_level: 33
        ),
      Trekmap.Me.Fleet.drydock3_id() =>
        hunt_maradeurs(Trekmap.Me.Fleet.Setups.kumari_set(),
          fraction_ids: [@fraction_klingon],
          patrol_systems: faction_patrol_systems,
          min_targets_in_system: 5,
          min_target_level: 29,
          max_target_level: 33
        ),
      Trekmap.Me.Fleet.drydock4_id() =>
        defend_hive_or_station(Trekmap.Me.Fleet.Setups.vahklas_with_station_defence_set())
    }
  end

  def elite_faction_hunting_mission_plan do
    %{
      Trekmap.Me.Fleet.drydock1_id() =>
        hunt_maradeurs(Trekmap.Me.Fleet.Setups.mayflower_set(),
          fraction_ids: [@fraction_neutral_or_elite],
          patrol_systems: @klingon_elite_systems,
          min_targets_in_system: 3,
          min_target_level: 21,
          max_target_level: 25
        ),
      Trekmap.Me.Fleet.drydock2_id() =>
        hunt_maradeurs(Trekmap.Me.Fleet.Setups.north_star_set(),
          fraction_ids: [@fraction_neutral_or_elite],
          patrol_systems: @klingon_elite_systems,
          min_targets_in_system: 3,
          min_target_level: 21,
          max_target_level: 25
        ),
      Trekmap.Me.Fleet.drydock3_id() =>
        hunt_maradeurs(Trekmap.Me.Fleet.Setups.kumari_set(),
          fraction_ids: [@fraction_neutral_or_elite],
          patrol_systems: @klingon_elite_systems,
          min_targets_in_system: 3,
          min_target_level: 21,
          max_target_level: 25
        ),
      Trekmap.Me.Fleet.drydock4_id() =>
        defend_hive_or_station(Trekmap.Me.Fleet.Setups.vahklas_with_station_defence_set())
    }
  end

  def blockade_mission_plan(target_station) do
    if target_station.player.level < 27 do
      %{
        Trekmap.Me.Fleet.drydock1_id() =>
          block_enemy_station(Trekmap.Me.Fleet.Setups.mayflower_set(),
            target_station: target_station
          ),
        Trekmap.Me.Fleet.drydock2_id() =>
          block_enemy_station(Trekmap.Me.Fleet.Setups.north_star_set(),
            target_station: target_station
          ),
        Trekmap.Me.Fleet.drydock3_id() =>
          block_enemy_station(Trekmap.Me.Fleet.Setups.kumari_set(),
            target_station: target_station
          ),
        Trekmap.Me.Fleet.drydock4_id() =>
          defend_hive_or_station(Trekmap.Me.Fleet.Setups.vahklas_with_station_defence_set())
      }
    else
      %{
        Trekmap.Me.Fleet.drydock1_id() =>
          defend_hive_or_station(Trekmap.Me.Fleet.Setups.mayflower_set()),
        Trekmap.Me.Fleet.drydock2_id() =>
          block_enemy_station(Trekmap.Me.Fleet.Setups.phindra_set(),
            target_station: target_station
          ),
        Trekmap.Me.Fleet.drydock3_id() =>
          block_enemy_station(Trekmap.Me.Fleet.Setups.fortunate_set(),
            target_station: target_station
          ),
        Trekmap.Me.Fleet.drydock4_id() =>
          block_enemy_station(Trekmap.Me.Fleet.Setups.orion_set(),
            target_station: target_station
          )
      }
    end
  end

  def loot_mission_plan(target_station) do
    %{
      Trekmap.Me.Fleet.drydock1_id() =>
        loot_station(Trekmap.Me.Fleet.Setups.envoy1_set(),
          target_station: target_station
        ),
      Trekmap.Me.Fleet.drydock2_id() =>
        loot_station(Trekmap.Me.Fleet.Setups.envoy2_set(),
          target_station: target_station
        ),
      Trekmap.Me.Fleet.drydock3_id() =>
        loot_station(Trekmap.Me.Fleet.Setups.envoy3_set(),
          target_station: target_station
        ),
      Trekmap.Me.Fleet.drydock4_id() =>
        loot_station(Trekmap.Me.Fleet.Setups.horizon_set(),
          target_station: target_station
        ),
      "mission_observer" =>
        {Trekmap.Bots.FleetCommander.Observers.RaidObserver,
         [
           target_station: target_station
         ]}
    }
  end

  def raid_mission_plan(%{strength: strength} = target_station) when strength < 0 do
    loot_mission_plan(target_station)
  end

  def raid_mission_plan(target_station) do
    %{
      Trekmap.Me.Fleet.drydock1_id() =>
        break_station(Trekmap.Me.Fleet.Setups.mayflower_set(),
          target_station: target_station
        ),
      Trekmap.Me.Fleet.drydock2_id() =>
        break_station(Trekmap.Me.Fleet.Setups.north_star_set(),
          target_station: target_station
        ),
      Trekmap.Me.Fleet.drydock3_id() =>
        break_station(Trekmap.Me.Fleet.Setups.kumari_set(),
          target_station: target_station
        ),
      Trekmap.Me.Fleet.drydock4_id() =>
        loot_station(Trekmap.Me.Fleet.Setups.weak_horizon_set(),
          target_station: target_station
        ),
      "mission_observer" =>
        {Trekmap.Bots.FleetCommander.Observers.RaidObserver,
         [
           target_station: target_station
         ]}
    }
  end

  def raid_mission_plan do
    multitasking_mission_plan()
    |> Map.put("mission_observer", {Trekmap.Bots.FleetCommander.Observers.RaidObserver, []})
  end
end
