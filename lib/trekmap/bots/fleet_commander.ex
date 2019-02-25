defmodule Trekmap.Bots.FleetCommander do
  use GenServer
  alias Trekmap.Me.Fleet
  require Logger

  @patrol_systems [
    # Dlith,
    958_423_648,
    1_017_582_787,
    # 2** raw
    81250,
    83345,
    81459,
    81497,
    601_072_182,
    1_854_874_708,
    1_718_038_036,
    849_541_812,
    1_790_049_115,
    1_462_287_177,
    1_083_794_899,
    # 3** raw
    830_770_182,
    1_133_522_720,
    81531,
    2_102_605_227,
    1_747_858_074,
    625_581_925,
    186_798_495,
    1_691_252_927,
    717_782_925,
    955_177_926,
    1_016_428_829,
    739_609_161,
    1_744_652_289
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[FleetCommander] Waiting for commands")
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, allies} = Trekmap.Galaxy.Alliances.list_allies()
    {:ok, enemies} = Trekmap.Galaxy.Alliances.list_enemies()
    allies = Enum.map(allies, & &1.tag)
    enemies = Enum.map(enemies, & &1.tag)
    {:ok, %{session: session, on_mission: false, enemies: enemies, allies: allies}}
  end

  def continue_missions do
    GenServer.cast(__MODULE__, :continue_missions)
  end

  def stop_missions do
    GenServer.cast(__MODULE__, :stop_missions)
  end

  def handle_cast(:stop_missions, %{session: session} = state) do
    Logger.info("[FleetCommander] Stopping all missions and recalling fleet")
    :ok = recall_all_fleet(session)
    {:noreply, %{state | on_mission: false}}
  end

  def handle_cast(:continue_missions, %{session: session, on_mission: false} = state) do
    fleet = get_initial_fleet(session)
    Logger.info("[FleetCommander] Starting missions using fleet: #{inspect(fleet.id)}")
    send(self(), {:continue_mission, fleet})
    {:noreply, %{state | on_mission: true}}
  end

  def handle_cast(:continue_missions, %{on_mission: true} = state) do
    {:noreply, state}
  end

  def handle_info({:continue_mission, _fleet}, %{on_mission: false} = state) do
    {:noreply, state}
  end

  def handle_info({:continue_mission, %{state: :fighting}}, %{session: session} = state) do
    Logger.info("[FleetCommander] Fleet is fighting")

    :timer.sleep(:timer.seconds(5))
    fleet = reload_jelly_fleet(session)
    send(self(), {:continue_mission, fleet})

    {:noreply, state}
  end

  def handle_info({:continue_mission, %{state: :mining}}, %{session: session} = state) do
    fleet = reload_jelly_fleet(session)
    Logger.info("[FleetCommander] Fleet is mining, hiding at #{inspect(fleet.coords)}")

    with {:ok, fleet} <- Trekmap.Me.fly_to_coords(fleet, fleet.coords, session) do
      send(self(), {:continue_mission, %{fleet | state: :idle}})
    else
      _other ->
        send(self(), {:continue_mission, %{fleet | state: :idle}})
    end

    {:noreply, state}
  end

  def handle_info({:continue_mission, %{state: fleet_state} = fleet}, %{session: session} = state)
      when fleet_state in [:warping, :flying, :charging] do
    Logger.info(
      "[FleetCommander] Fleet is #{inspect(fleet_state)}, " <>
        "remaining_duration: #{inspect(fleet.remaining_travel_time)}"
    )

    :timer.sleep(:timer.seconds(fleet.remaining_travel_time + 1))
    fleet = reload_jelly_fleet(session)
    send(self(), {:continue_mission, fleet})

    {:noreply, state}
  end

  def handle_info(
        {:continue_mission, %{hull_health: hull_health} = fleet},
        %{session: session} = state
      )
      when hull_health < 50 do
    Logger.info("[FleetCommander] Fleet hull is damaged #{hull_health}, recalling")

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

  # The game does not update shield damage in api resource
  # def handle_info(
  #       {:continue_mission, %{shield_health: shield_health} = fleet},
  #       %{session: session} = state
  #     )
  #     when shield_health < 50 do
  #   Logger.info("[FleetCommander] Fleet shield is damaged #{shield_health}, waiting")
  #
  #   Trekmap.Me.fly_to_coords(fleet, fleet.coords, session)
  #   :timer.sleep(:timer.seconds(10))
  #   fleet = get_initial_fleet(session)
  #   Process.send_after(self(), {:continue_mission, fleet}, :timer.seconds(30))
  #
  #   {:noreply, state}
  # end

  def handle_info(
        {:continue_mission, %{cargo_bay_size: cargo_bay_size, cargo_size: cargo_size} = fleet},
        %{session: session} = state
      )
      when cargo_bay_size * 0.95 < cargo_size do
    Logger.info("[FleetCommander] Fleet is full, recalling")

    case Trekmap.Me.recall_fleet(fleet, session) do
      {:ok, fleet} ->
        Process.send_after(self(), {:continue_mission, fleet}, :timer.seconds(10))

      {:error, :in_warp} ->
        :timer.sleep(:timer.seconds(fleet.remaining_travel_time))
        fleet = get_initial_fleet(session)
        Process.send_after(self(), {:continue_mission, fleet}, :timer.seconds(10))

      {:error, :fleet_on_repair} ->
        Trekmap.Me.full_repair(session)
        fleet = get_initial_fleet(session)
        send(self(), {:continue_mission, fleet})

      :ok ->
        fleet = get_initial_fleet(session)
        send(self(), {:continue_mission, fleet})
    end

    {:noreply, state}
  end

  def handle_info({:continue_mission, fleet}, %{on_mission: true} = state) do
    Logger.debug("[FleetCommander] Continue, #{inspect(fleet, pretty: true)}")
    %{session: session, enemies: enemies, allies: allies} = state
    {:ok, targets} = find_targets_in_current_system(fleet, enemies, allies, session)

    {fleet, continue} =
      targets
      |> Enum.sort_by(&distance(&1.coords, fleet.coords))
      |> Enum.reduce_while({fleet, :next_system}, fn target, {fleet, _next_step} ->
        if distance(target.coords, fleet.coords) < 50 do
          Logger.info(
            "[FleetCommander] Killing [#{target.player.alliance.tag}] #{target.player.name}, " <>
              "score: #{inspect(target.bounty_score)} at #{to_string(target.system.name)}"
          )

          case Trekmap.Me.attack_miner(fleet, target, session) do
            {:ok, fleet} ->
              :timer.sleep(:timer.seconds(fleet.remaining_travel_time) + 3)
              fleet = reload_jelly_fleet(session)
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
              Logger.warn("[FleetCommander] Cant kill #{inspect({target, other}, pretty: true)}")
              {:cont, {fleet, :next_system}}
          end
        else
          case Trekmap.Me.fly_to_coords(fleet, target.coords, session) do
            {:ok, fleet} ->
              Logger.info(
                "[FleetCommander] Approaching [#{target.player.alliance.tag}] " <>
                  "#{target.player.name} " <>
                  "eta #{to_string(fleet.remaining_travel_time)} " <>
                  "at #{to_string(target.system.name)}"
              )

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
              Logger.warn(
                "[FleetCommander] Cant approach #{inspect({target, other}, pretty: true)}"
              )

              {:cont, {fleet, :current_system}}
          end
        end
      end)

    case continue do
      :next_system ->
        nearby_systems_with_targets =
          Enum.sort_by(@patrol_systems, fn system_id ->
            path = Trekmap.Galaxy.find_path(session.galaxy, fleet.system_id, system_id)
            Trekmap.Galaxy.get_path_distance(session.galaxy, path)
          end)
          |> Enum.filter(fn system_id ->
            system = Trekmap.Me.get_system(system_id, session)
            {:ok, targets} = find_targets_in_system(fleet, system, enemies, allies, session)
            length(targets) > 5
          end)

        if length(nearby_systems_with_targets) > 0 do
          system_id = List.first(nearby_systems_with_targets)
          Logger.info("[FleetCommander] Warping to next system #{system_id}")

          with {:ok, fleet} <- Trekmap.Me.warp_to_system(fleet, system_id, session) do
            Process.send_after(
              self(),
              {:continue_mission, fleet},
              :timer.seconds(fleet.remaining_travel_time)
            )
          else
            {:error, :in_warp} ->
              fleet = reload_jelly_fleet(session)

              Process.send_after(
                self(),
                {:continue_mission, fleet},
                :timer.seconds(fleet.remaining_travel_time)
              )
          end
        else
          Logger.info("[FleetCommander] No more targets in any systems")

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
        Logger.info("[FleetCommander] Shield is active, delaying missions by 1 hour")

        :ok = recall_all_fleet(session)

        Process.send_after(
          self(),
          {:continue_mission, fleet},
          :timer.minutes(60)
        )
    end

    {:noreply, state}
  end

  def reload_jelly_fleet(session) do
    {:ok, {_starbase, _fleets, deployed_fleets}} = Trekmap.Me.fetch_current_state(session)
    jellyfish = Map.fetch!(deployed_fleets, to_string(Fleet.jellyfish_fleet_id()))
    Fleet.build(jellyfish)
  end

  def get_initial_fleet(session) do
    {:ok, {_starbase, _fleets, deployed_fleets}} = Trekmap.Me.fetch_current_state(session)

    cond do
      deployed_fleets == %{} ->
        Logger.info("[FleetCommander] No fleets deployed, picking jellyfish")
        fleet = %Fleet{id: Fleet.jellyfish_fleet_id(), system_id: session.home_system_id}
        Logger.info("[FleetCommander] Repairing ships before mission")
        Trekmap.Me.full_repair(session)
        :timer.sleep(1_000)
        {:ok, fleet} = Trekmap.Me.fly_to_coords(fleet, {0, 0}, session)
        fleet

      jellyfish = Map.get(deployed_fleets, to_string(Fleet.jellyfish_fleet_id())) ->
        Logger.info("[FleetCommander] Jellyfish is already deployed")
        Fleet.build(jellyfish)

      true ->
        Logger.info("[FleetCommander] Jellyfish is not deployed, recalling all ships")
        :ok = recall_all_fleet(session, [Fleet.jellyfish_fleet_id()])
        Logger.info("[FleetCommander] Repairing ships before mission")
        Trekmap.Me.full_repair(session)
        :timer.sleep(1_000)
        fleet = %Fleet{id: Fleet.jellyfish_fleet_id(), system_id: session.home_system_id}
        {:ok, fleet} = Trekmap.Me.fly_to_coords(fleet, {0, 0}, session)
        fleet
    end
  end

  defp find_targets_in_current_system(fleet, enemies, allies, session) do
    system = Trekmap.Me.get_system(fleet.system_id, session)
    find_targets_in_system(fleet, system, enemies, allies, session)
  end

  defp find_targets_in_system(fleet, system, enemies, allies, session) do
    with {:ok, {_stations, miners}} <-
           Trekmap.Galaxy.System.list_miners(system, session) do
      targets =
        miners
        |> Enum.filter(&can_attack?(&1, allies))
        |> Enum.filter(&can_kill?(&1, fleet))
        |> Enum.filter(&should_kill?(&1, enemies))

      {:ok, targets}
    end
  end

  defp can_attack?(miner, allies) do
    {x, y} = miner.coords

    ally? = if miner.player.alliance, do: miner.player.alliance.tag in allies, else: false

    not ally? and not is_nil(x) and not is_nil(y) and
      miner.player.level > 16 and miner.player.level < 23 and not is_nil(miner.mining_node_id)
  end

  defp can_kill?(miner, fleet) do
    if miner.strength do
      miner.strength * 1.3 < fleet.strength
    else
      false
    end
  end

  defp should_kill?(miner, enemies) do
    enemy? = if miner.player.alliance, do: miner.player.alliance.tag in enemies, else: false

    enemy? or miner.bounty_score > 1800
  end

  defp distance({x1, y1}, {x2, y2}) do
    x1 - x2 + (y1 - y2)
  end

  defp recall_all_fleet(session, except \\ []) do
    Logger.info("[FleetCommander] Recalling all fleet")
    {:ok, {_starbase, _fleets, deployed_fleets}} = Trekmap.Me.fetch_current_state(session)

    deployed_fleets
    |> Enum.reject(fn {_id, %{"fleet_id" => fleet_id}} -> fleet_id in except end)
    |> Enum.each(fn {_id, deployed_fleet} ->
      Fleet.build(deployed_fleet)
      |> Trekmap.Me.recall_fleet(session)
      |> case do
        {:ok, fleet} ->
          Logger.info("[FleetCommander] Fleet recalled, current state: #{to_string(fleet.state)}")

        :ok ->
          Logger.info("[FleetCommander] Fleet recalled, returned to base")

        other ->
          Logger.error("[FleetCommander] Failed to recall fleet, reason: #{inspect(other)}")
      end
    end)
  end
end