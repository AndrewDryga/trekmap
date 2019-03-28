defmodule Trekmap.Bots.FleetCommander.Strategies.FractionHunter do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, session) do
    max_warp_distance = Keyword.fetch!(config, :max_warp_distance)

    {:ok, prohibited_systems} = Trekmap.Galaxy.System.list_prohibited_systems()
    prohibited_system_ids = Enum.map(prohibited_systems, & &1.id)

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
       fraction_ids: Keyword.fetch!(config, :fraction_ids),
       patrol_systems: patrol_systems,
       min_targets_in_system: Keyword.fetch!(config, :min_targets_in_system),
       min_target_level: Keyword.fetch!(config, :min_target_level),
       max_target_level: Keyword.fetch!(config, :max_target_level),
       skip_nearest_system?: Keyword.fetch!(config, :skip_nearest_system?)
     }}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    {:instant_repair, config}
  end

  def handle_continue(%{hull_health: hull_health}, _session, config)
      when hull_health < 33 do
    {:recall, config}
  end

  def handle_continue(fleet, session, config) do
    %{patrol_systems: patrol_systems} = config

    {:ok, targets, pursuiters} = find_targets_in_current_system(fleet, session, config)

    name = Trekmap.Bots.FleetCommander.StartshipActor.name(fleet.id)

    need_evacuation? = need_evacuation?(fleet, pursuiters)
    if need_evacuation?, do: Logger.warn("[#{name}] Need to leave, pursuiters are nearby")

    if length(targets) > 0 and not need_evacuation? and fleet.system_id in patrol_systems do
      target =
        targets
        |> Enum.sort_by(&safe_distance(&1.coords, fleet.coords, pursuiters))
        |> List.first()

      {{:attack, target}, config}
    else
      if nearby_system_with_targets = find_targets_in_nearby_system(fleet, session, config) do
        {system, targets} = nearby_system_with_targets
        target = List.first(targets)
        {{:fly, system, target.coords}, config}
      else
        Logger.info("[#{name}] Can't find any targets")
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
      fraction_ids: fraction_ids,
      min_target_level: min_target_level,
      max_target_level: max_target_level
    } = config

    with {:ok, %{hostiles: hostiles}} <- Trekmap.Galaxy.System.scan_system(system, session) do
      targets =
        hostiles
        |> Enum.filter(&enemy_fraction?(&1, fraction_ids))
        |> Enum.filter(&should_kill?(&1, min_target_level, max_target_level))
        |> Enum.filter(&can_kill?(&1, fleet))

      pursuiters = Enum.filter(hostiles, &(&1.pursuit_fleet_id == fleet.id))

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

    {nearby_system_with_targets, _second?} =
      Enum.sort_by(patrol_systems, fn system_id ->
        path = Trekmap.Galaxy.find_path(session.galaxy, fleet.system_id, system_id)
        Trekmap.Galaxy.get_path_distance(session.galaxy, path)
      end)
      |> Enum.reduce_while({nil, not skip_nearest_system?}, fn system_id, {acc, should_stop?} ->
        system = Trekmap.Me.get_system(system_id, session)
        {:ok, targets, _pursuiters} = find_targets_in_system(fleet, system, session, config)

        cond do
          length(targets) > min_targets_in_system and should_stop? ->
            {:halt, {{system, targets}, true}}

          length(targets) > min_targets_in_system ->
            {:cont, {{system, targets}, true}}

          true ->
            {:cont, {acc, should_stop?}}
        end
      end)

    nearby_system_with_targets
  end

  defp enemy_fraction?(marauder, fraction_ids) do
    marauder.fraction_id in fraction_ids
  end

  defp should_kill?(marauder, min_target_level, max_target_level) do
    min_target_level <= marauder.level and marauder.level <= max_target_level
  end

  defp can_kill?(marauder, fleet) do
    cond do
      is_nil(fleet.strength) -> marauder.strength < 150_000
      not is_nil(marauder.strength) -> marauder.strength < fleet.strength
      true -> false
    end
  end

  defp safe_distance({x1, y1}, {x2, y2}, []) do
    distance({x1, y1}, {x2, y2})
  end

  defp safe_distance({x1, y1}, {x2, y2}, pursuiters) do
    sum_of_target_distances_to_pursuiters =
      pursuiters
      |> Enum.map(&distance(&1.coords, {x1, y1}))
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
