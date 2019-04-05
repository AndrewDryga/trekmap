defmodule Trekmap.Bots.FleetCommander.Strategies.HiveDefender do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, session) do
    {:ok, allies} = Trekmap.Galaxy.Alliances.list_nap()
    {:ok, enemies} = Trekmap.Galaxy.Alliances.list_kos_in_hive()
    {:ok, bad_people} = Trekmap.Galaxy.Player.list_bad_people()
    hive_systems = Enum.map(session.hive_system_ids, &Trekmap.Me.get_system(&1, session))

    allies = Enum.map(allies, & &1.tag)
    enemies = Enum.map(enemies, & &1.tag)
    bad_people_ids = Enum.map(bad_people, & &1.id)

    {:ok,
     %{
       in_hive?: session.home_system_id in session.hive_system_ids,
       hive_systems: hive_systems,
       allies: allies,
       enemies: enemies,
       bad_people_ids: bad_people_ids,
       min_target_level: Keyword.fetch!(config, :min_target_level),
       max_target_level: Keyword.fetch!(config, :max_target_level)
     }}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    Trekmap.Locker.unlock_caller_locks()
    {:instant_repair, config}
  end

  def handle_continue(_fleet, _session, %{in_hive?: false} = config) do
    {:recall, config}
  end

  def handle_continue(%{state: :at_dock} = fleet, session, config) do
    {:ok, targets} = find_targets_in_hive_systems(fleet, session, config)

    targets = Enum.reject(targets, &Trekmap.Locker.locked?(&1.id))

    if length(targets) > 0 do
      target =
        targets
        |> Enum.sort_by(&distance(&1.coords, fleet.coords))
        |> Enum.take(3)
        |> Enum.random()

      system = Trekmap.Me.get_system(fleet.system_id, session)
      {{:fly, system, target.coords}, config}
    else
      Trekmap.Locker.unlock_caller_locks()
      {{:wait, :timer.seconds(5)}, config}
    end
  end

  def handle_continue(fleet, session, config) do
    {:ok, targets} = find_targets_in_hive_systems(fleet, session, config)

    targets = Enum.reject(targets, &Trekmap.Locker.locked?(&1.id))

    if length(targets) > 0 do
      target =
        targets
        |> Enum.sort_by(&distance(&1.coords, fleet.coords))
        |> List.first()

      Trekmap.Locker.lock(target.id)

      if target.system.id == fleet.system_id do
        alliance_tag = if target.player.alliance, do: "[#{target.player.alliance.tag}] ", else: ""
        {x, y} = target.coords

        Trekmap.Discord.send_message(
          "Killing: #{alliance_tag}#{target.player.name}  " <>
            "at [S:#{target.system.id} X:#{x} Y:#{y}] system #{target.system.name}."
        )

        {{:attack, target}, config}
      else
        {{:fly, target.system, target.coords}, config}
      end
    else
      Trekmap.Locker.unlock_caller_locks()
      {:recall, config}
    end
  end

  defp find_targets_in_hive_systems(fleet, session, config) do
    %{hive_systems: hive_systems} = config

    Enum.reduce_while(hive_systems, {:ok, []}, fn system, return ->
      with {:ok, []} <- find_targets_in_system(system, fleet, session, config) do
        {:cont, return}
      else
        other -> {:halt, other}
      end
    end)
  end

  defp find_targets_in_system(system, fleet, session, config) do
    %{
      allies: allies,
      enemies: enemies,
      bad_people_ids: bad_people_ids,
      min_target_level: min_target_level,
      max_target_level: max_target_level
    } = config

    with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(system, session),
         {:ok, %{spacecrafts: spacecrafts}} <-
           Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session) do
      targets =
        spacecrafts
        |> Enum.reject(&ally?(&1, allies))
        |> Enum.filter(&can_kill?(&1, fleet))
        |> Enum.filter(&can_attack?(&1, min_target_level, max_target_level))
        |> Enum.filter(&should_kill?(&1, enemies, bad_people_ids))

      {:ok, targets}
    else
      {:error, %{"code" => 400}} = error ->
        Logger.error("Can't list targets in system #{inspect(system)}, reason: #{inspect(error)}")
        :timer.sleep(5_000)
        find_targets_in_system(system, fleet, session, config)
    end
  end

  def ally?(ship, allies) do
    if ship.player.alliance, do: ship.player.alliance.tag in allies, else: false
  end

  defp can_kill?(ship, fleet) do
    if is_nil(fleet.strength) do
      ship.strength < 250_000
    else
      ship.strength < fleet.strength
    end
  end

  defp can_attack?(ship, min_target_level, max_target_level) do
    min_target_level <= ship.player.level and ship.player.level <= max_target_level
  end

  defp should_kill?(ship, enemies, bad_people_ids) do
    has_alliance? = not is_nil(ship.player.alliance)
    enemy? = if has_alliance?, do: ship.player.alliance.tag in enemies, else: false
    should_suffer? = ship.player.id in bad_people_ids

    enemy? or should_suffer?
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end
end
