defmodule Trekmap.Bots.FleetCommander.Strategies.MinerHunter do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, session) do
    {:ok, allies} = Trekmap.Galaxy.Alliances.list_nap()
    {:ok, enemies} = Trekmap.Galaxy.Alliances.list_enemies()
    {:ok, bad_alliances} = Trekmap.Galaxy.Alliances.list_bad_alliances()
    {:ok, bad_people} = Trekmap.Galaxy.Player.list_bad_people()
    {:ok, kos_people} = Trekmap.Galaxy.Player.list_kos_people()

    {:ok, prohibited_systems} = Trekmap.Galaxy.System.list_prohibited_systems()
    prohibited_system_ids = Enum.map(prohibited_systems, & &1.id)

    hive_systems = Enum.map(session.hive_system_ids, &Trekmap.Me.get_system(&1, session))

    allies = Enum.map(allies, & &1.tag)
    enemies = Enum.map(enemies, & &1.tag)
    bad_alliances = Enum.map(bad_alliances, & &1.tag)
    bad_people_ids = Enum.map(bad_people, & &1.id)
    kos_people_ids = Enum.map(kos_people, & &1.id)

    max_warp_distance = Keyword.fetch!(config, :max_warp_distance)

    # ++ session.hive_system_ids)
    patrol_systems =
      Keyword.fetch!(config, :patrol_systems)
      |> Enum.filter(fn system_id ->
        path = Trekmap.Galaxy.find_path(session.galaxy, session.home_system_id, system_id)
        warp_distance = Trekmap.Galaxy.get_path_max_warp_distance(session.galaxy, path)
        warp_distance <= max_warp_distance
      end)
      |> Enum.reject(&(&1 in prohibited_system_ids))

    {:ok,
     %{
       in_hive?: session.home_system_id in session.hive_system_ids,
       hive_systems: hive_systems,
       allies: allies,
       enemies: enemies,
       bad_alliances: bad_alliances,
       bad_people_ids: bad_people_ids,
       kos_people_ids: kos_people_ids,
       patrol_systems: patrol_systems,
       min_targets_in_system: Keyword.fetch!(config, :min_targets_in_system),
       min_target_level: Keyword.fetch!(config, :min_target_level),
       max_target_level: Keyword.fetch!(config, :max_target_level),
       min_target_bounty_score: Keyword.fetch!(config, :min_target_bounty_score),
       skip_nearest_system?: Keyword.get(config, :skip_nearest_system?, false)
     }}
  end

  def handle_continue(%{state: :mining} = fleet, session, config) do
    system = Trekmap.Me.get_system(fleet.system_id, session)
    {{:fly, system, fleet.coords}, config}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    Trekmap.Locker.unlock_caller_locks()
    {:instant_repair, config}
  end

  def handle_continue(%{hull_health: hull_health}, _session, config)
      when hull_health < 33 do
    Trekmap.Locker.unlock_caller_locks()
    {:recall, config}
  end

  def handle_continue(%{cargo_bay_size: cargo_bay_size, cargo_size: cargo_size}, _session, config)
      when cargo_bay_size * 0.9 < cargo_size do
    Trekmap.Locker.unlock_caller_locks()
    {:recall, config}
  end

  def handle_continue(fleet, session, config) do
    {:ok, targets, pursuiters} = find_targets_in_current_system(fleet, session, config)

    name = Trekmap.Bots.FleetCommander.StartshipActor.name(fleet.id)

    need_evacuation? = need_evacuation?(fleet, pursuiters)
    if need_evacuation?, do: Logger.warn("[#{name}] Need to leave, pursuiters are nearby")

    targets = Enum.reject(targets, &Trekmap.Locker.locked?(&1.id))

    if length(targets) > 0 and not need_evacuation? do
      target =
        targets
        |> Enum.sort_by(&safe_distance(&1.coords, fleet.coords, pursuiters))
        |> List.first()

      Trekmap.Locker.lock(target.id)

      if distance(target.coords, fleet.coords) < 7 do
        {{:attack, target}, config}
      else
        system = Trekmap.Me.get_system(fleet.system_id, session)
        {{:fly, system, target.coords}, config}
      end
    else
      cond do
        nearby_system_with_targets = find_targets_in_nearby_system(fleet, session, config) ->
          {system, targets} = nearby_system_with_targets
          target = List.first(targets)
          Trekmap.Locker.lock(target.id)
          {{:fly, system, target.coords}, config}

        # fleet.state == :at_dock ->
        #   Trekmap.Locker.unlock_caller_locks()
        #   HiveDefender.handle_continue(fleet, session, config)

        true ->
          Logger.info("[#{name}] Can't find any targets")
          Trekmap.Locker.unlock_caller_locks()
          {:recall, config}
      end
    end
  end

  defp need_evacuation?(_fleet, []), do: false

  defp need_evacuation?(fleet, pursuiters) do
    nearest_pursuiter_distance =
      pursuiters
      |> Enum.map(&distance(&1.coords, fleet.coords))
      |> Enum.sort()
      |> List.first()

    max_pursuiter_strength =
      pursuiters
      |> Enum.sort_by(& &1.strength, &>=/2)
      |> List.first()

    if max_pursuiter_strength > fleet.strength * 0.8 do
      nearest_pursuiter_distance < 150
    else
      false
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
      kos_people_ids: kos_people_ids,
      min_target_level: min_target_level,
      max_target_level: max_target_level,
      min_target_bounty_score: min_target_bounty_score
    } = config

    with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(system, session),
         {:ok, %{spacecrafts: miners}} <-
           Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session) do
      targets =
        miners
        |> Enum.reject(&ally?(&1, allies))
        |> Enum.filter(&can_kill?(&1, fleet))
        |> Enum.filter(&can_attack?(&1, min_target_level, max_target_level))
        |> Enum.filter(
          &should_kill?(
            &1,
            min_target_bounty_score,
            enemies,
            bad_alliances,
            bad_people_ids,
            kos_people_ids
          )
        )

      pursuiters = Enum.filter(miners, &(&1.pursuit_fleet_id == fleet.id))

      {:ok, targets, pursuiters}
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
        {:ok, targets, _pursuiters} = find_targets_in_system(fleet, system, session, config)

        cond do
          length(targets) >= min_targets_in_system and should_stop? ->
            {:halt, {{system, targets}, true}}

          length(targets) >= min_targets_in_system ->
            {:cont, {{system, targets}, true}}

          true ->
            {:cont, {acc, should_stop?}}
        end
      end)

    nearby_system_with_targets
  end

  def ally?(miner, allies) do
    if miner.player.alliance, do: miner.player.alliance.tag in allies, else: false
  end

  defp can_kill?(miner, fleet) do
    cond do
      is_nil(fleet.strength) -> true
      not is_nil(miner.strength) -> miner.strength < fleet.strength
      true -> false
    end
  end

  defp can_attack?(miner, min_target_level, max_target_level) do
    min_target_level <= miner.player.level and miner.player.level <= max_target_level
  end

  defp should_kill?(
         miner,
         min_target_bounty_score,
         enemies,
         bad_alliances,
         bad_people_ids,
         kos_people_ids
       ) do
    overcargo? = not is_nil(miner.bounty_score) and miner.bounty_score > 1

    bad_alliance? =
      if miner.player.alliance, do: miner.player.alliance.tag in bad_alliances, else: false

    kos_person? = miner.player.id in kos_people_ids
    bad_person? = miner.player.id in bad_people_ids
    should_suffer? = (bad_person? or bad_alliance?) and overcargo?
    enemy? = if miner.player.alliance, do: miner.player.alliance.tag in enemies, else: false
    over_bounty_score? = overcargo? and miner.bounty_score > min_target_bounty_score

    enemy? or kos_person? or should_suffer? or over_bounty_score?
  end

  defp safe_distance({x1, y1}, {x2, y2}, []) do
    distance({x1, y1}, {x2, y2})
  end

  defp safe_distance({x1, y1}, {x2, y2}, pursuiters) do
    sum_of_target_distances_to_pursuiters =
      pursuiters
      |> Enum.map(&distance(&1.coords, {x2, y2}))
      |> Enum.sum()

    sum_of_cource_angles_to_pursuiters =
      pursuiters
      |> Enum.map(&vector_abs_angle(&1.coords, {x1, y1}, {x2, y2}))
      |> Enum.sum()

    distance({x1, y1}, {x2, y2}) *
      sum_of_target_distances_to_pursuiters *
      sum_of_cource_angles_to_pursuiters
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end

  defp vector_abs_angle({x1, y1}, {x2, y2}, {x3, y3}) do
    {v1x, v1y} = {x3 - x2, y3 - y2}
    {v2x, v2y} = {x3 - x1, y3 - y1}

    mag1 = :math.sqrt(:math.pow(v1x, 2) + :math.pow(v1y, 2))
    mag2 = :math.sqrt(:math.pow(v2x, 2) + :math.pow(v2y, 2))
    mag = mag1 * mag2

    if mag == 0 do
      0
    else
      :math.cos((v1x * v2x + v1y * v2y) / mag) * (180 / :math.pi())
    end
  end
end
