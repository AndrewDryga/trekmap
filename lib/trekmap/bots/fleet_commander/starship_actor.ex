defmodule Trekmap.Bots.FleetCommander.StartshipActor do
  use GenServer
  alias Trekmap.Me.Fleet
  alias Trekmap.Galaxy.{Spacecraft, Marauder}
  require Logger

  ### Public API

  # TODO: No need to reload fleet if we just fly
  # switching mission plans:
  # 2 ships on miners, 1 at home;
  # 1 ship on heavy miners 2 at home;
  # 1 heavy + 1 small + 1 at home;
  # 1 ship initiating raids, 2 at home
  # 2 ships grabbing raid loot, 1 at home
  # Notify mission controller when ship is at dock and return is triggered, then mission is idle
  # and we can switch to another mission

  def pause_mission(pid), do: GenServer.cast(pid, :pause_mission)
  def pause_mission(pid, nil), do: GenServer.cast(pid, :pause_mission)
  def pause_mission(pid, timeout), do: GenServer.cast(pid, {:pause_mission, timeout})
  def unpause_mission(pid), do: GenServer.cast(pid, :unpause_mission)
  def continue_mission(pid), do: GenServer.cast(pid, :continue_mission)

  ### Bot Server

  def start_link({fleet_id, strategy, strategy_config}) do
    GenServer.start_link(__MODULE__, {fleet_id, strategy, strategy_config}, name: name(fleet_id))
  end

  def child_spec(fleet_id) do
    Supervisor.child_spec(
      %{
        id: fleet_id,
        start: {__MODULE__, :start_link, [fleet_id]}
      },
      []
    )
  end

  @impl true
  def init({fleet_id, strategy, strategy_config}) do
    Logger.info("[#{name(fleet_id)}] On mission #{inspect(strategy)}")
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, strategy_state} = strategy.init(strategy_config, session)

    state = %{
      session: session,
      fleet_id: fleet_id,
      fleet: nil,
      strategy: strategy,
      strategy_state: strategy_state,
      clearence_granted: false,
      mission_paused: false,
      pause_timer_ref: nil
    }

    {:ok, state, 0}
  end

  @impl true
  def handle_cast(:pause_mission, state) do
    if not state.mission_paused do
      Logger.info("[#{name(state.fleet_id)}] Pausing mission")
    end

    {:noreply, %{state | mission_paused: true}}
  end

  @impl true
  def handle_cast({:pause_mission, timeout}, state) do
    if not state.mission_paused do
      Logger.info("[#{name(state.fleet_id)}] Pausing mission for #{trunc(timeout / 60)} seconds")
    end

    state = schedule_unpase(timeout, state)
    {:noreply, %{state | mission_paused: true}}
  end

  @impl true
  def handle_cast(:continue_mission, state) do
    {:noreply, %{state | clearence_granted: true}}
  end

  @impl true
  def handle_cast(:unpause_mission, state) do
    if state.mission_paused do
      Logger.info("[#{name(state.fleet_id)}] Unpausing mission")
    end

    if state.pause_timer_ref do
      Process.cancel_timer(state.pause_timer_ref)
    end

    {:noreply, %{state | mission_paused: false, pause_timer_ref: nil}}
  end

  @impl true
  def handle_info(:unpause_mission, state) do
    if state.mission_paused do
      Logger.info("[#{name(state.fleet_id)}] Unpausing mission by timeout")
    end

    if state.pause_timer_ref do
      Process.cancel_timer(state.pause_timer_ref)
    end

    {:noreply, %{state | mission_paused: false, pause_timer_ref: nil}}
  end

  @impl true
  def handle_info(:timeout, state) do
    continue_and_reload_fleet()
    {:noreply, state}
  end

  @impl true
  def handle_info({:continue, nil}, %{session: session, fleet_id: fleet_id} = state) do
    fleet = fetch_fleet(fleet_id, session)
    continue(fleet)

    Trekmap.Bots.Admiral.update_fleet_report(%{
      clearence_granted: state.clearence_granted,
      mission_paused: state.mission_paused,
      strategy: state.strategy,
      fleet_id: state.fleet_id,
      fleet: fleet
    })

    {:noreply, %{state | fleet: fleet}}
  end

  @impl true
  def handle_info({:continue, %{state: fleet_state} = fleet}, state)
      when fleet_state in [:warping, :charging] do
    continue_and_reload_fleet(:timer.seconds(fleet.remaining_travel_time + 1))
    {:noreply, state}
  end

  @impl true
  def handle_info({:continue, fleet}, %{clearence_granted: false} = state) do
    Logger.debug("[#{name(state.fleet_id)}] Awaiting clearence")
    continue(fleet, 5_000)
    {:noreply, state}
  end

  @impl true
  def handle_info({:continue, fleet}, %{mission_paused: nil} = state) do
    continue(fleet, 5_000)
    {:noreply, state}
  end

  @impl true
  def handle_info({:continue, %{state: :at_dock} = fleet}, %{mission_paused: true} = state) do
    continue(fleet, 5_000)
    {:noreply, state}
  end

  @impl true
  def handle_info({:continue, fleet}, %{mission_paused: true} = state) do
    perform_fleet_action(fleet, :recall, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:continue, %{state: :fighting}}, state) do
    continue_and_reload_fleet(:timer.seconds(5))
    {:noreply, state}
  end

  @impl true
  def handle_info({:continue, %{state: :flying} = fleet}, state) do
    continue_and_reload_fleet(:timer.seconds(fleet.remaining_travel_time + 1))
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:continue, fleet},
        %{session: session, strategy: strategy, strategy_state: strategy_state} = state
      ) do
    {action, strategy_state} = strategy.handle_continue(fleet, session, strategy_state)
    perform_fleet_action(fleet, action, state)
    {:noreply, %{state | strategy_state: strategy_state}}
  end

  defp schedule_unpase(timeout, state) do
    if state.pause_timer_ref do
      Process.cancel_timer(state.pause_timer_ref)
    end

    pause_timer_ref = Process.send_after(self(), :continue_mission, timeout)

    %{state | pause_timer_ref: pause_timer_ref}
  end

  def continue_and_reload_fleet(timeout \\ 5_000) do
    continue(nil, timeout)
  end

  def continue(fleet, timeout \\ 0)

  def continue(fleet, 0) do
    send(self(), {:continue, fleet})
  end

  def continue(fleet, timeout) do
    Process.send_after(self(), {:continue, fleet}, timeout)
  end

  def perform_fleet_action(
        %{state: :at_dock},
        :instant_repair,
        %{session: session, fleet_id: fleet_id}
      ) do
    Logger.debug("[#{name(fleet_id)}] Repairing all fleet")
    :ok = Trekmap.Me.full_repair(session)
    continue_and_reload_fleet(1_000)
  end

  def perform_fleet_action(%{state: :at_dock} = fleet, :recall, _state) do
    continue(fleet, 5_000)
  end

  def perform_fleet_action(fleet, :recall, %{session: session, fleet_id: fleet_id}) do
    Logger.debug("[#{name(fleet_id)}] Recalling fleet")

    case Trekmap.Me.recall_fleet(fleet, session) do
      {:ok, fleet} ->
        if not is_nil(fleet.system_id) and fleet.system_id != session.home_system_id do
          fleet = %{fleet | state: :charging, remaining_travel_time: 6}
          continue_and_reload_fleet(:timer.seconds(fleet.remaining_travel_time))
        else
          continue_and_reload_fleet(:timer.seconds(fleet.remaining_travel_time))
        end

      {:error, :in_warp} ->
        continue_and_reload_fleet(0)

      {:error, :fleet_on_repair} ->
        continue_and_reload_fleet(0)

      :ok ->
        continue_and_reload_fleet(0)
    end
  end

  def perform_fleet_action(
        %{system_id: system_id} = fleet,
        {:fly, %{id: system_id} = system, coords},
        %{session: session, fleet_id: fleet_id}
      ) do
    Logger.debug("[#{name(fleet_id)}] Flying to coords in the same system #{inspect(coords)}")

    with {:ok, fleet} <- Trekmap.Me.fly_to_coords(fleet, coords, session) do
      continue_and_reload_fleet(:timer.seconds(fleet.remaining_travel_time))
    else
      other ->
        Logger.warn("Can't fly to system #{inspect({system, coords})}, reason: #{inspect(other)}")
        continue_and_reload_fleet(0)
    end
  end

  def perform_fleet_action(
        fleet,
        {:fly, system, coords},
        %{session: session, fleet_id: fleet_id}
      ) do
    Logger.debug("[#{name(fleet_id)}] Warping to #{inspect(coords)} in system #{system.name}")

    with {:ok, fleet} <- Trekmap.Me.warp_to_system(fleet, system.id, coords, session) do
      continue_and_reload_fleet(:timer.seconds(fleet.remaining_travel_time))
    else
      other ->
        Logger.warn("Can't fly to system #{inspect({system, coords})}, reason: #{inspect(other)}")
        continue_and_reload_fleet(0)
    end
  end

  def perform_fleet_action(
        fleet,
        {:attack, %Spacecraft{} = target},
        %{session: session, fleet_id: fleet_id} = state
      ) do
    alliance_tag = if target.player.alliance, do: "[#{target.player.alliance.tag}] ", else: ""

    Logger.info(
      "[#{name(fleet_id)}] Killing #{alliance_tag}#{target.player.name}, " <>
        "score: #{inspect(target.bounty_score)} at #{to_string(target.system.name)}"
    )

    case Trekmap.Me.attack_miner(fleet, target, session) do
      {:ok, fleet} ->
        if fleet.state == :flying and fleet.remaining_travel_time < 2 do
          continue_and_reload_fleet(5_000)
        else
          continue(fleet)
        end

      {:error, :in_warp} ->
        continue_and_reload_fleet(0)

      {:error, :fleet_on_repair} ->
        continue_and_reload_fleet(0)

      {:error, :shield_is_enabled} ->
        Logger.warn("Can not attack spacecraft because shield is enabled")
        perform_fleet_action(fleet, :recall, state)

      other ->
        Logger.warn("Cant kill #{inspect({target, other}, pretty: true)}")
        continue_and_reload_fleet(0)
    end
  end

  def perform_fleet_action(fleet, {:attack, %Marauder{} = target}, %{session: session}) do
    Logger.info(
      "[FractionHunter] Killing marauder #{target.fraction_id} lvl #{target.level}, " <>
        "strength: #{inspect(target.strength)} at #{to_string(target.system.name)}"
    )

    case Trekmap.Me.attack_spacecraft(fleet, target, session) do
      {:ok, fleet} ->
        continue(fleet)

      {:error, :in_warp} ->
        continue_and_reload_fleet(0)

      {:error, :fleet_on_repair} ->
        continue_and_reload_fleet(0)

      other ->
        Logger.warn("Cant kill #{inspect({target, other}, pretty: true)}")
        continue_and_reload_fleet(0)
    end
  end

  def perform_fleet_action(fleet, {:wait, timeout}, %{fleet_id: fleet_id}) do
    Logger.debug("[#{name(fleet_id)}] Waiting #{timeout}")
    continue(fleet, timeout)
  end

  def fetch_fleet(fleet_id, session) do
    {:ok, {_starbase, fleets, deployed_fleets, ships, _battle_results}} =
      Trekmap.Me.fetch_current_state(session)

    if deployed_fleet = Map.get(deployed_fleets, to_string(fleet_id)) do
      Fleet.build(deployed_fleet)
    else
      %{"ship_ids" => [ship_id]} = Map.fetch!(fleets, to_string(fleet_id))
      %{"max_hp" => max_hp, "damage" => damage} = Map.fetch!(ships, to_string(ship_id))
      hull_health = 100 - Enum.max([0, damage]) / (max_hp / 100)
      %Fleet{id: fleet_id, system_id: session.home_system_id, hull_health: hull_health}
    end
  end

  def name(771_246_931_724_024_704), do: :"#{__MODULE__}.Fleet_Jellyfish"
  def name(771_331_774_860_311_262), do: :"#{__MODULE__}.Fleet_NorthStar"
  def name(791_687_022_921_464_764), do: :"#{__MODULE__}.Fleet_Kehra"
  def name(fleet_id), do: :"#{__MODULE__}.Fleet_#{to_string(fleet_id)}"
end
