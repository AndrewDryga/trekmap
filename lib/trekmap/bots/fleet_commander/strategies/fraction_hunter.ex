defmodule Trekmap.Bots.FleetCommander.Strategies.FractionHunter do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, _session) do
    {:ok,
     %{
       exclude_fraction_ids: Keyword.fetch!(config, :exclude_fraction_ids),
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
      exclude_fraction_ids: exclude_fraction_ids,
      min_target_level: min_target_level,
      max_target_level: max_target_level
    } = config

    with {:ok, hostiles} <-
           Trekmap.Galaxy.System.list_hostiles(system, session) do
      targets =
        hostiles
        |> Enum.filter(&enemy_fraction?(&1, exclude_fraction_ids))
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

  defp enemy_fraction?(marauder, exclude_fraction_ids) do
    marauder.fraction_id not in exclude_fraction_ids
  end

  defp should_kill?(marauder, min_target_level, max_target_level) do
    min_target_level < marauder.level and marauder.level < max_target_level
  end

  defp can_kill?(marauder, fleet) do
    cond do
      is_nil(fleet.strength) -> true
      not is_nil(marauder.strength) -> marauder.strength < fleet.strength * 1.2
      true -> false
    end
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end
end

# defmodule Trekmap.Bots.FleetCommander.Strategies.FractionHunter do
#   use GenServer
#   alias Trekmap.Me.Fleet
#   require Logger
#
# @patrol_systems [
#   1_984_126_753,
#   355_503_878,
#   1_731_519_518,
#   975_691_590,
#   1_691_252_927,
#   1_744_652_289,
#   846_029_245,
#   1_780_286_771,
#   1_358_992_189
# ]

#   def handle_info({:continue_mission, fleet}, %{on_mission: true, session: session} = state) do
#     Logger.debug("[FractionHunter] Continue, #{inspect(fleet, pretty: true)}")
#     {:ok, targets} = find_targets_in_current_system(fleet, session)
#
#     {fleet, continue} =
#       targets
#       |> Enum.sort_by(&distance(&1.coords, fleet.coords))
#       |> Enum.reduce_while({fleet, :next_system}, fn target, {fleet, _next_step} ->
#         Logger.info(
#           "[FractionHunter] Killing #{target.fraction_id} lvl #{target.level}, " <>
#             "strength: #{inspect(target.strength)} at #{to_string(target.system.name)}"
#         )
#
#         case Trekmap.Me.attack_spacecraft(fleet, target, session) do
#           {:ok, fleet} ->
#             :timer.sleep(:timer.seconds(fleet.remaining_travel_time) + 3)
#             fleet = reload_ns_fleet(session)
#             {:halt, {fleet, :current_system}}
#
#           {:error, :in_warp} ->
#             fleet = get_initial_fleet(session)
#             {:halt, {fleet, :current_system}}
#
#           {:error, :fleet_on_repair} ->
#             fleet = get_initial_fleet(session)
#             {:halt, {fleet, :current_system}}
#
#           {:error, :shield_is_enabled} ->
#             {:halt, {fleet, :recall}}
#
#           other ->
#             Logger.warn("[FractionHunter] Cant kill #{inspect({target, other}, pretty: true)}")
#             {:cont, {fleet, :next_system}}
#         end
#       end)
#
#     case continue do
#       :next_system ->
#         nearby_system_with_targets =
#           Enum.sort_by(@patrol_systems, fn system_id ->
#             path = Trekmap.Galaxy.find_path(session.galaxy, fleet.system_id, system_id)
#             Trekmap.Galaxy.get_path_distance(session.galaxy, path)
#           end)
#           |> Enum.reduce_while(nil, fn system_id, acc ->
#             system = Trekmap.Me.get_system(system_id, session)
#             {:ok, targets} = find_targets_in_system(fleet, system, session)
#
#             if length(targets) > 3 do
#               {:halt, {system, targets}}
#             else
#               {:cont, acc}
#             end
#           end)
#
#         if nearby_system_with_targets do
#           {system, targets} = nearby_system_with_targets
#           target = List.first(targets)
#           Logger.info("[FractionHunter] Warping to next system #{system.name} (#{system.id})")
#
#           with {:ok, fleet} <- Trekmap.Me.warp_to_system(fleet, system.id, target.coords, session) do
#             Process.send_after(
#               self(),
#               {:continue_mission, fleet},
#               :timer.seconds(fleet.remaining_travel_time)
#             )
#           else
#             {:error, :in_warp} ->
#               fleet = reload_ns_fleet(session)
#
#               Process.send_after(
#                 self(),
#                 {:continue_mission, fleet},
#                 :timer.seconds(fleet.remaining_travel_time)
#               )
#           end
#         else
#           Logger.info("[FractionHunter] No more targets in any systems")
#
#           :ok = recall_fleet(session)
#           :timer.sleep(10_000)
#
#           fleet = reload_ns_fleet(session)
#
#           Process.send_after(
#             self(),
#             {:continue_mission, fleet},
#             :timer.seconds(fleet.remaining_travel_time)
#           )
#         end
#
#       :current_system ->
#         Process.send_after(
#           self(),
#           {:continue_mission, fleet},
#           :timer.seconds(fleet.remaining_travel_time + 3)
#         )
#
#       :recall ->
#         Logger.info("[FractionHunter] Shield is active, continue")
#
#         Process.send_after(
#           self(),
#           {:continue_mission, fleet},
#           :timer.minutes(60)
#         )
#     end
#
#     {:noreply, state}
#   end
#

#
#   defp find_targets_in_current_system(fleet, session) do
#     system = Trekmap.Me.get_system(fleet.system_id, session)
#     find_targets_in_system(fleet, system, session)
#   end
#
# defp find_targets_in_system(fleet, system, session) do
#   with {:ok, hostiles} <-
#          Trekmap.Galaxy.System.list_hostiles(system, session) do
#     targets =
#       hostiles
#       |> Enum.filter(&can_kill?(&1, fleet))
#
#     {:ok, targets}
#   end
#   end
#
#   defp can_kill?(marauder, fleet) do
#     marauder.strength * 0.8 < fleet.strength and marauder.level > 23 and marauder.level < 28 and
#       marauder.fraction_id != -1
#   end
#
#   defp distance({x1, y1}, {x2, y2}) do
#     x1 - x2 + (y1 - y2)
#   end
#
#   defp recall_fleet(session) do
#     {:ok, {_starbase, _fleets, deployed_fleets}} = Trekmap.Me.fetch_current_state(session)
#
#     if northstar = Map.get(deployed_fleets, to_string(Fleet.northstar_fleet_id())) do
#       Logger.info("[FractionHunter] Recalling  fleet")
#
#       Fleet.build(northstar)
#       |> Trekmap.Me.recall_fleet(session)
#       |> case do
#         {:ok, fleet} ->
#           Logger.info("[FractionHunter] Fleet recalled, current state: #{to_string(fleet.state)}")
#
#         :ok ->
#           Logger.info("[FractionHunter] Fleet recalled, returned to base")
#
#         other ->
#           Logger.error("[FractionHunter] Failed to recall fleet, reason: #{inspect(other)}")
#       end
#     else
#       :ok
#     end
#   end
# end