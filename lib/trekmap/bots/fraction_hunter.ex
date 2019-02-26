defmodule Trekmap.Bots.FractionHunter do
  use GenServer
  alias Trekmap.Me.Fleet
  require Logger

  @patrol_systems [
    1_984_126_753,
    355_503_878,
    1_731_519_518,
    975_691_590,
    1_691_252_927,
    1_744_652_289,
    846_029_245,
    1_780_286_771,
    1_358_992_189
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[FractionHunter] Waiting for commands")
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()

    {:ok, %{session: session, on_mission: false}}
  end

  def continue_missions do
    GenServer.cast(__MODULE__, :continue_missions)
  end

  def stop_missions do
    GenServer.cast(__MODULE__, :stop_missions)
  end

  def get_ships_on_mission(timeout \\ 500) do
    try do
      GenServer.call(__MODULE__, :get_ships_on_mission, timeout)
    catch
      :exit, _ -> []
    end
  end

  def handle_call(:get_ships_on_mission, _from, %{on_mission: true} = state) do
    {:reply, [Fleet.northstar_fleet_id()], state}
  end

  def handle_call(:get_ships_on_mission, _from, %{on_mission: false} = state) do
    {:reply, [], state}
  end

  def handle_cast(:stop_missions, state) do
    {:noreply, %{state | on_mission: false}}
  end

  def handle_cast(:continue_missions, %{session: session, on_mission: false} = state) do
    fleet = get_initial_fleet(session)
    Logger.info("[FractionHunter] Starting missions using fleet: #{inspect(fleet.id)}")
    send(self(), {:continue_mission, fleet})
    {:noreply, %{state | on_mission: true}}
  end

  def handle_cast(:continue_missions, %{on_mission: true} = state) do
    {:noreply, state}
  end

  def handle_info({:continue_mission, _fleet}, %{on_mission: false} = state) do
    {:noreply, state}
  end

  def handle_info({:continue_mission, %{state: :at_dock}}, %{session: session} = state) do
    Logger.info("[FractionHunter] Fleet is at docks")

    Trekmap.Me.full_repair(session)
    fleet = get_initial_fleet(session)
    send(self(), {:continue_mission, fleet})

    {:noreply, state}
  end

  def handle_info({:continue_mission, %{state: :fighting}}, %{session: session} = state) do
    Logger.info("[FractionHunter] Fleet is fighting")

    :timer.sleep(:timer.seconds(5))
    fleet = reload_ns_fleet(session)
    send(self(), {:continue_mission, fleet})

    {:noreply, state}
  end

  def handle_info({:continue_mission, %{state: fleet_state} = fleet}, %{session: session} = state)
      when fleet_state in [:warping, :flying, :charging] do
    Logger.info(
      "[FractionHunter] Fleet is #{inspect(fleet_state)}, " <>
        "remaining_duration: #{inspect(fleet.remaining_travel_time)}"
    )

    :timer.sleep(:timer.seconds(fleet.remaining_travel_time + 1))
    fleet = reload_ns_fleet(session)
    send(self(), {:continue_mission, fleet})

    {:noreply, state}
  end

  def handle_info(
        {:continue_mission, %{hull_health: hull_health} = fleet},
        %{session: session} = state
      )
      when hull_health < 33 do
    Logger.info("[FractionHunter] Fleet hull is damaged #{hull_health}, recalling")

    case Trekmap.Me.recall_fleet(fleet, session) do
      {:ok, fleet} ->
        Process.send_after(self(), {:continue_mission, fleet}, :timer.seconds(10))

      {:error, :in_warp} ->
        :timer.sleep(:timer.seconds(fleet.remaining_travel_time))
        fleet = get_initial_fleet(session)
        Process.send_after(self(), {:continue_mission, fleet}, :timer.seconds(10))

      {:error, :fleet_on_repair} ->
        Trekmap.Me.full_repair(session)
        :timer.sleep(1_000)
        fleet = get_initial_fleet(session)
        send(self(), {:continue_mission, fleet})

      :ok ->
        Trekmap.Me.full_repair(session)
        fleet = get_initial_fleet(session)
        send(self(), {:continue_mission, fleet})
    end

    {:noreply, state}
  end

  def handle_info({:continue_mission, fleet}, %{on_mission: true, session: session} = state) do
    Logger.debug("[FractionHunter] Continue, #{inspect(fleet, pretty: true)}")
    {:ok, targets} = find_targets_in_current_system(fleet, session)

    {fleet, continue} =
      targets
      |> Enum.sort_by(&distance(&1.coords, fleet.coords))
      |> Enum.reduce_while({fleet, :next_system}, fn target, {fleet, _next_step} ->
        Logger.info(
          "[FractionHunter] Killing #{target.fraction_id} lvl #{target.level}, " <>
            "strength: #{inspect(target.strength)} at #{to_string(target.system.name)}"
        )

        case Trekmap.Me.attack_spacecraft(fleet, target, session) do
          {:ok, fleet} ->
            :timer.sleep(:timer.seconds(fleet.remaining_travel_time) + 3)
            fleet = reload_ns_fleet(session)
            {:halt, {fleet, :current_system}}

          {:error, :in_warp} ->
            fleet = get_initial_fleet(session)
            {:halt, {fleet, :current_system}}

          {:error, :fleet_on_repair} ->
            fleet = get_initial_fleet(session)
            {:halt, {fleet, :current_system}}

          {:error, :shield_is_enabled} ->
            {:halt, {fleet, :recall}}

          other ->
            Logger.warn("[FractionHunter] Cant kill #{inspect({target, other}, pretty: true)}")
            {:cont, {fleet, :next_system}}
        end
      end)

    case continue do
      :next_system ->
        nearby_system_with_targets =
          Enum.sort_by(@patrol_systems, fn system_id ->
            path = Trekmap.Galaxy.find_path(session.galaxy, fleet.system_id, system_id)
            Trekmap.Galaxy.get_path_distance(session.galaxy, path)
          end)
          |> Enum.reduce_while(nil, fn system_id, acc ->
            system = Trekmap.Me.get_system(system_id, session)
            {:ok, targets} = find_targets_in_system(fleet, system, session)

            if length(targets) > 3 do
              {:halt, {system, targets}}
            else
              {:cont, acc}
            end
          end)

        if nearby_system_with_targets do
          {system, targets} = nearby_system_with_targets
          target = List.first(targets)
          Logger.info("[FractionHunter] Warping to next system #{system.name} (#{system.id})")

          with {:ok, fleet} <- Trekmap.Me.warp_to_system(fleet, system.id, target.coords, session) do
            Process.send_after(
              self(),
              {:continue_mission, fleet},
              :timer.seconds(fleet.remaining_travel_time)
            )
          else
            {:error, :in_warp} ->
              fleet = reload_ns_fleet(session)

              Process.send_after(
                self(),
                {:continue_mission, fleet},
                :timer.seconds(fleet.remaining_travel_time)
              )
          end
        else
          Logger.info("[FractionHunter] No more targets in any systems")

          :ok = recall_fleet(session)
          :timer.sleep(10_000)

          fleet = reload_ns_fleet(session)

          Process.send_after(
            self(),
            {:continue_mission, fleet},
            :timer.seconds(fleet.remaining_travel_time)
          )
        end

      :current_system ->
        Process.send_after(
          self(),
          {:continue_mission, fleet},
          :timer.seconds(fleet.remaining_travel_time + 3)
        )

      :recall ->
        Logger.info("[FractionHunter] Shield is active, continue")

        Process.send_after(
          self(),
          {:continue_mission, fleet},
          :timer.minutes(60)
        )
    end

    {:noreply, state}
  end

  def reload_ns_fleet(session) do
    {:ok, {_starbase, _fleets, deployed_fleets}} = Trekmap.Me.fetch_current_state(session)

    if deployed_fleets == %{} do
      %Fleet{id: Fleet.northstar_fleet_id(), system_id: session.home_system_id}
    else
      northstar = Map.fetch!(deployed_fleets, to_string(Fleet.northstar_fleet_id()))
      Fleet.build(northstar)
    end
  end

  def get_initial_fleet(session) do
    {:ok, {_starbase, _fleets, deployed_fleets}} = Trekmap.Me.fetch_current_state(session)

    cond do
      deployed_fleets == %{} ->
        Logger.info("[FractionHunter] No fleets deployed, picking northstar")
        fleet = %Fleet{id: Fleet.northstar_fleet_id(), system_id: session.home_system_id}
        Logger.info("[FractionHunter] Repairing ships before mission")
        Trekmap.Me.full_repair(session)
        :timer.sleep(1_000)
        {:ok, fleet} = Trekmap.Me.fly_to_coords(fleet, {0, 0}, session)
        fleet

      northstar = Map.get(deployed_fleets, to_string(Fleet.northstar_fleet_id())) ->
        Logger.info("[FractionHunter] North Star is already deployed")
        Fleet.build(northstar)

      true ->
        Logger.info("[FractionHunter] North Star is not deployed, recalling all ships")
        :ok = recall_fleet(session)
        Logger.info("[FractionHunter] Repairing ships before mission")
        Trekmap.Me.full_repair(session)
        :timer.sleep(1_000)
        fleet = %Fleet{id: Fleet.northstar_fleet_id(), system_id: session.home_system_id}
        {:ok, fleet} = Trekmap.Me.fly_to_coords(fleet, {0, 0}, session)
        fleet
    end
  end

  defp find_targets_in_current_system(fleet, session) do
    system = Trekmap.Me.get_system(fleet.system_id, session)
    find_targets_in_system(fleet, system, session)
  end

  defp find_targets_in_system(fleet, system, session) do
    with {:ok, hostiles} <-
           Trekmap.Galaxy.System.list_hostiles(system, session) do
      targets =
        hostiles
        |> Enum.filter(&can_kill?(&1, fleet))

      {:ok, targets}
    end
  end

  defp can_kill?(marauder, fleet) do
    marauder.strength * 0.8 < fleet.strength and marauder.level > 23 and marauder.level < 28
  end

  defp distance({x1, y1}, {x2, y2}) do
    x1 - x2 + (y1 - y2)
  end

  defp recall_fleet(session) do
    Logger.info("[FractionHunter] Recalling all fleet")
    {:ok, {_starbase, _fleets, deployed_fleets}} = Trekmap.Me.fetch_current_state(session)

    if northstar = Map.get(deployed_fleets, to_string(Fleet.northstar_fleet_id())) do
      Fleet.build(northstar)
      |> Trekmap.Me.recall_fleet(session)
      |> case do
        {:ok, fleet} ->
          Logger.info("[FractionHunter] Fleet recalled, current state: #{to_string(fleet.state)}")

        :ok ->
          Logger.info("[FractionHunter] Fleet recalled, returned to base")

        other ->
          Logger.error("[FractionHunter] Failed to recall fleet, reason: #{inspect(other)}")
      end
    else
      :ok
    end
  end
end
