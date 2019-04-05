defmodule Trekmap.Bots.FleetCommander.Strategies.Miner do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, session) do
    {:ok, allies} = Trekmap.Galaxy.Alliances.list_nap()
    {:ok, prohibited_systems} = Trekmap.Galaxy.System.list_prohibited_systems()

    allies = Enum.map(allies, & &1.tag)
    prohibited_system_ids = Enum.map(prohibited_systems, & &1.id)

    max_warp_distance = Keyword.fetch!(config, :max_warp_distance)

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
       allies: allies,
       patrol_systems: patrol_systems,
       min_target_level: Keyword.fetch!(config, :min_target_level),
       max_target_level: Keyword.fetch!(config, :max_target_level),
       resource_name_filters: Keyword.get(config, :resource_name_filters, "***")
     }}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    Trekmap.Locker.unlock_caller_locks()
    {:instant_repair, config}
  end

  def handle_continue(%{hull_health: hull_health}, _session, config)
      when hull_health < 40 do
    Trekmap.Locker.unlock_caller_locks()
    {:recall, config}
  end

  def handle_continue(%{cargo_bay_size: cargo_bay_size, cargo_size: cargo_size}, _session, config)
      when cargo_bay_size * 0.9 < cargo_size do
    Trekmap.Locker.unlock_caller_locks()
    {:recall, config}
  end

  def handle_continue(
        %{protected_cargo_size: protected_cargo_size, cargo_size: cargo_size},
        _session,
        config
      )
      when protected_cargo_size + 500 < cargo_size do
    Trekmap.Locker.unlock_caller_locks()
    {:recall, config}
  end

  def handle_continue(%{state: :mining, mining_node: nil} = fleet, session, config) do
    system = Trekmap.Me.get_system(fleet.system_id, session)

    with {:ok, %{mining_nodes: mining_nodes}} <-
           Trekmap.Galaxy.System.scan_system(system, session),
         mining_node when not is_nil(mining_node) <-
           Enum.find(mining_nodes, &(&1.occupied_by_fleet_id == fleet.id)) do
      %{
        is_active: is_active,
        remaining_count: remaining_count,
        occupied_at: occupied_at
      } = mining_node

      mining_node = %{mining_node | coords: fleet.coords}

      cond do
        not is_active ->
          Logger.info("Resetting node, not active")
          {{:mine, mining_node}, config}

        remaining_count < 1 ->
          Logger.info("Resetting node, depleted")
          {{:mine, mining_node}, config}

        NaiveDateTime.diff(NaiveDateTime.utc_now(), occupied_at, :second) > 60 * 3 ->
          Logger.info("Resetting cargo by ttl")
          {{:mine, mining_node}, config}

        true ->
          {{:wait, :timer.minutes(1)}, config}
      end
    else
      _other ->
        Logger.warn("Can't find node")
        {{:wait, :timer.minutes(1)}, config}
    end
  end

  def handle_continue(fleet, session, config) do
    {:ok, targets} = find_targets_in_current_system(fleet, session, config)

    targets = Enum.reject(targets, &Trekmap.Locker.locked?(&1.id))

    if length(targets) > 0 do
      target =
        targets
        |> Enum.sort_by(&distance(&1.coords, fleet.coords))
        |> List.first()

      Trekmap.Locker.lock(target.id)

      if distance(target.coords, fleet.coords) < 7 do
        case target do
          %Trekmap.Galaxy.System.MiningNode{} = mining_node ->
            {{:mine, mining_node}, config}

          %Trekmap.Galaxy.Spacecraft{} = spacecraft ->
            {{:attack, spacecraft}, config}
        end
      else
        Trekmap.Locker.lock(target.id)
        {{:fly, target.system, target.coords}, config}
      end
    else
      cond do
        nearby_system_with_targets = find_targets_in_nearby_system(fleet, session, config) ->
          {system, targets} = nearby_system_with_targets
          target = List.first(targets)
          Trekmap.Locker.lock(target.id)
          {{:fly, system, target.coords}, config}

        true ->
          name = Trekmap.Bots.FleetCommander.StartshipActor.name(fleet.id)
          Logger.info("[#{name}] Can't find any targets")
          Trekmap.Locker.unlock_caller_locks()
          {{:wait, :timer.minutes(3)}, config}
      end
    end
  end

  defp find_targets_in_current_system(fleet, session, config) do
    system = Trekmap.Me.get_system(fleet.system_id, session)
    find_targets_in_system(fleet, system, session, config)
  end

  defp find_targets_in_system(fleet, system, session, config) do
    %{
      allies: allies,
      min_target_level: min_target_level,
      max_target_level: max_target_level,
      resource_name_filters: resource_name_filters
    } = config

    with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(system, session),
         {:ok, %{spacecrafts: miners, mining_nodes: _mining_nodes}} <-
           Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session) do
      # targets =
      #   mining_nodes
      #   |> Enum.filter(& &1.is_active)
      #   |> Enum.filter(&String.contains?(&1.resource_name, resource_name_filters))
      #   |> Enum.reject(& &1.is_occupied)
      #
      # targets =
      #   if length(targets) > 0 do
      #     targets
      #   else
      targets =
        miners
        |> Enum.reject(&ally?(&1, allies))
        |> Enum.reject(&is_nil(&1.mining_node))
        |> Enum.filter(&String.contains?(&1.mining_node.resource_name, resource_name_filters))
        |> Enum.filter(&can_kill?(&1, fleet))
        |> Enum.filter(&can_attack?(&1, min_target_level, max_target_level))

      # end

      {:ok, targets}
    else
      {:error, %{"code" => 400}} = error ->
        Logger.error("Can't list targets in system #{inspect(system)}, reason: #{inspect(error)}")
        :timer.sleep(5_000)
        find_targets_in_system(fleet, system, session, config)
    end
  end

  defp find_targets_in_nearby_system(fleet, session, config) do
    %{patrol_systems: patrol_systems} = config

    min_targets_in_system = 1
    stop_on_first_result? = true

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
      not is_nil(miner.strength) -> miner.strength * 1.2 < fleet.strength
      true -> false
    end
  end

  defp can_attack?(miner, min_target_level, max_target_level) do
    overcargo? = not is_nil(miner.bounty_score) and miner.bounty_score > 1

    min_target_level <= miner.player.level and miner.player.level <= max_target_level and
      overcargo?
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end
end
