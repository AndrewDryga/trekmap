defmodule Trekmap.Bots.FleetCommander.Strategies.FractionHunter do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, _session) do
    {:ok,
     %{
       fraction_ids: Keyword.fetch!(config, :fraction_ids),
       patrol_systems: Keyword.fetch!(config, :patrol_systems),
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
    {:ok, targets} = find_targets_in_current_system(fleet, session, config)

    if length(targets) > 0 do
      target =
        targets
        |> Enum.sort_by(&distance(&1.coords, fleet.coords))
        |> List.first()

      {{:attack, target}, config}
    else
      if nearby_system_with_targets = find_targets_in_nearby_system(fleet, session, config) do
        {system, targets} = nearby_system_with_targets
        target = List.first(targets)
        {{:fly, system, target.coords}, config}
      else
        name = Trekmap.Bots.FleetCommander.StartshipActor.name(fleet.id)
        Logger.info("[#{name}] Can't find any targets")
        {:recall, config}
      end
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

    {nearby_system_with_targets, _second?} =
      Enum.sort_by(patrol_systems, fn system_id ->
        path = Trekmap.Galaxy.find_path(session.galaxy, fleet.system_id, system_id)
        Trekmap.Galaxy.get_path_distance(session.galaxy, path)
      end)
      |> Enum.reduce_while({nil, not skip_nearest_system?}, fn system_id, {acc, should_stop?} ->
        system = Trekmap.Me.get_system(system_id, session)
        {:ok, targets} = find_targets_in_system(fleet, system, session, config)

        cond do
          length(targets) > min_targets_in_system and should_stop? ->
            {:halt, {{system, targets}, true}}

          length(targets) > min_targets_in_system ->
            {:cont, {{system, targets}, true}}

          true ->
            {:cont, {acc, false}}
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
      is_nil(fleet.strength) -> true
      not is_nil(marauder.strength) -> marauder.strength < fleet.strength * 1.3
      true -> false
    end
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end
end
