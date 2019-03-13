defmodule Trekmap.Bots.FleetCommander.Observers.RaidObserver do
  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def abort(station) do
    GenServer.cast(__MODULE__, {:abort, station})
  end

  @impl true
  def init(config) do
    Logger.info("[#{inspect(__MODULE__)}] Starting")
    target_station = Keyword.get(config, :target_station)
    {:ok, %{target_station: target_station}, 0}
  end

  @impl true
  def handle_info(:timeout, %{target_station: nil} = state) do
    Logger.info("[#{inspect(__MODULE__)}] Looking for a raid target")
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()

    with {:noreply, state} <- find_and_raid_next(state, session) do
      Process.send_after(self(), :timeout, 60_000)
      {:noreply, state}
    else
      other ->
        Process.send_after(self(), :timeout, 60_000)
        Logger.warn("[#{inspect(__MODULE__)}] Can't find new raid targets. #{inspect(other)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    Process.send_after(self(), :timeout, 60_000)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:abort, %{id: id} = station}, %{target_station: %{id: id}} = state) do
    Logger.info("[#{inspect(__MODULE__)}] Aborting raid")

    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()

    Logger.info("[#{inspect(__MODULE__)}] Scanning raided system")
    station = Trekmap.AirDB.preload(station, [:system, :player, :planet])

    station = %{
      station
      | player: Trekmap.AirDB.preload(station.player, :alliance),
        shield_expires_at: nil
    }

    Trekmap.Bots.GalaxyScanner.sync_station(station.system, station)

    with {:noreply, state} <- find_and_raid_next(state, session) do
      {:noreply, state}
    else
      other ->
        Logger.warn("[#{inspect(__MODULE__)}] Can't find new raid targets. #{inspect(other)}")
        mission_plan = Trekmap.Bots.Admiral.raid_mission_plan()
        Trekmap.Bots.Admiral.set_mission_plan(mission_plan)
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:abort, _station}, state) do
    Logger.info("[#{inspect(__MODULE__)}] Already aborted")
    {:noreply, state}
  end

  def handle_cast(_other, state) do
    {:noreply, state}
  end

  defp find_and_raid_next(state, session) do
    with {:ok, raid_target} <- Trekmap.Galaxy.System.Station.fetch_raid_target(session) do
      Logger.info("[#{inspect(__MODULE__)}] Found new target #{inspect(raid_target)}")
      mission_plan = Trekmap.Bots.Admiral.raid_mission_plan(raid_target.id)
      Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

      {:noreply, %{state | target_station: raid_target}}
    end
  end
end
