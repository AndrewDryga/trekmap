defmodule Trekmap.Bots.FleetCommander.Strategies.Punisher do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, session) do
    {:ok, allies} = Trekmap.Galaxy.Alliances.list_nap()
    {:ok, enemies} = Trekmap.Galaxy.Alliances.list_enemies()
    {:ok, bad_alliances} = Trekmap.Galaxy.Alliances.list_bad_alliances()
    {:ok, bad_people} = Trekmap.Galaxy.Player.list_bad_people()

    allies = Enum.map(allies, & &1.tag)
    enemies = Enum.map(enemies, & &1.tag)
    bad_alliances = Enum.map(bad_alliances, & &1.tag)
    bad_people_ids = Enum.map(bad_people, & &1.id)

    bad_people_home_system_ids =
      Enum.flat_map(bad_people_ids, fn id ->
        with {:ok, station} <- Trekmap.Galaxy.System.Station.find_station(id) do
          [station.system.id]
        else
          _ -> []
        end
      end)

    max_warp_distance = Keyword.fetch!(config, :max_warp_distance)

    patrol_systems =
      (Keyword.fetch!(config, :patrol_systems) ++
         [session.hive_system_id] ++ bad_people_home_system_ids)
      |> Enum.filter(fn system_id ->
        path = Trekmap.Galaxy.find_path(session.galaxy, session.home_system_id, system_id)
        warp_distance = Trekmap.Galaxy.get_path_max_warp_distance(session.galaxy, path)
        warp_distance <= max_warp_distance
      end)

    {:ok,
     %{
       allies: allies,
       enemies: enemies,
       bad_alliances: bad_alliances,
       bad_people_ids: bad_people_ids,
       patrol_systems: patrol_systems,
       min_targets_in_system: Keyword.fetch!(config, :min_targets_in_system),
       min_target_level: Keyword.fetch!(config, :min_target_level),
       max_target_level: Keyword.fetch!(config, :max_target_level),
       skip_nearest_system?: Keyword.fetch!(config, :skip_nearest_system?)
     }}
  end

  def handle_continue(%{state: :mining} = fleet, session, config) do
    system = Trekmap.Me.get_system(fleet.system_id, session)
    {{:fly, system, fleet.coords}, config}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    {:instant_repair, config}
  end

  def handle_continue(%{hull_health: hull_health}, _session, config)
      when hull_health < 33 do
    {:recall, config}
  end

  def handle_continue(%{cargo_bay_size: cargo_bay_size, cargo_size: cargo_size}, _session, config)
      when cargo_bay_size * 0.7 < cargo_size do
    {:recall, config}
  end

  def handle_continue(fleet, session, config) do
    {:ok, targets} = find_targets_in_current_system(fleet, session, config)

    if length(targets) > 0 do
      target =
        targets
        |> Enum.sort_by(&distance(&1.coords, fleet.coords))
        |> List.first()

      if distance(target.coords, fleet.coords) < 7 do
        {{:attack, target}, config}
      else
        system = Trekmap.Me.get_system(fleet.system_id, session)
        {{:fly, system, target.coords}, config}
      end
    else
      if nearby_system_with_targets = find_targets_in_nearby_system(fleet, session, config) do
        {system, targets} = nearby_system_with_targets
        target = List.first(targets)
        {{:fly, system, target.coords}, config}
      else
        %{patrol_systems: patrol_systems} = config

        system_id =
          patrol_systems
          |> Enum.reject(&(&1 == fleet.system_id))
          |> Enum.sort_by(fn system_id ->
            path = Trekmap.Galaxy.find_path(session.galaxy, fleet.system_id, system_id)
            Trekmap.Galaxy.get_path_distance(session.galaxy, path)
          end)
          |> Enum.take(3)
          |> Enum.random()

        system = Trekmap.Me.get_system(system_id, session)
        {{:fly, system, {0, 0}}, config}
      end
    end
  end

  defp find_targets_in_current_system(fleet, session, config) do
    system = Trekmap.Me.get_system(fleet.system_id, session)
    find_targets_in_system(fleet, system, session, config)
  end

  defp find_targets_in_system(fleet, system, session, config) do
    %{
      enemies: enemies,
      allies: allies,
      bad_alliances: bad_alliances,
      bad_people_ids: bad_people_ids,
      min_target_level: min_target_level,
      max_target_level: max_target_level
    } = config

    with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(system, session),
         {:ok, %{spacecrafts: miners}} <-
           Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session) do
      targets =
        miners
        |> Enum.reject(&ally?(&1, allies))
        |> Enum.filter(&can_kill?(&1, fleet))
        |> Enum.filter(&can_attack?(&1, min_target_level, max_target_level))
        |> Enum.filter(&should_kill?(&1, enemies, bad_alliances, bad_people_ids))

      {:ok, targets}
    else
      {:error, %{"code" => 400}} = error ->
        Logger.error("Can't list targets in system #{inspect(system)}, reason: #{inspect(error)}")
        :timer.sleep(5_000)
        find_targets_in_system(fleet, system, session, config)
    end
  end

  defp find_targets_in_nearby_system(fleet, session, config) do
    %{
      patrol_systems: patrol_systems,
      min_targets_in_system: min_targets_in_system,
      skip_nearest_system?: skip_nearest_system?
    } = config

    stop_on_first_result? = not skip_nearest_system?

    {nearby_system_with_targets, _second?} =
      Enum.sort_by(patrol_systems, fn system_id ->
        path = Trekmap.Galaxy.find_path(session.galaxy, fleet.system_id, system_id)
        Trekmap.Galaxy.get_path_distance(session.galaxy, path)
      end)
      |> Enum.reduce_while({nil, stop_on_first_result?}, fn system_id, {acc, should_stop?} ->
        system = Trekmap.Me.get_system(system_id, session)
        {:ok, targets} = find_targets_in_system(fleet, system, session, config)

        cond do
          length(targets) >= min_targets_in_system and should_stop? ->
            {:halt, {{system, targets}, true}}

          length(targets) >= min_targets_in_system ->
            {:cont, {{system, targets}, true}}

          true ->
            {:cont, {acc, false}}
        end
      end)

    nearby_system_with_targets
  end

  def ally?(miner, allies) do
    if miner.player.alliance, do: miner.player.alliance.tag in allies, else: false
  end

  defp can_kill?(miner, fleet) do
    cond do
      is_nil(fleet.strength) -> miner.strength < 80_000
      not is_nil(miner.strength) -> miner.strength < fleet.strength
      true -> false
    end
  end

  defp can_attack?(miner, min_target_level, max_target_level) do
    min_target_level <= miner.player.level and miner.player.level <= max_target_level
  end

  defp should_kill?(miner, enemies, bad_alliances, bad_people_ids) do
    overcargo? = not is_nil(miner.bounty_score) and miner.bounty_score > 1

    bad_alliance? =
      if miner.player.alliance, do: miner.player.alliance.tag in bad_alliances, else: false

    bad_person? = miner.player.id in bad_people_ids
    should_suffer? = (bad_person? or bad_alliance?) and overcargo?

    enemy? = if miner.player.alliance, do: miner.player.alliance.tag in enemies, else: false

    enemy? or should_suffer?
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end
end
