defmodule Trekmap.Bots.GalaxyScanner do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[Galaxy Scanner] Looking for a good hunt")
    {:ok, session} = Trekmap.SessionManager.fetch_session()
    {:ok, %{session: session, systems: nil}, 0}
  end

  def handle_info(:timeout, %{session: session, systems: nil} = state) do
    Logger.info("[Galaxy Scanner] Scanning Galaxy")
    {:ok, systems} = Trekmap.Galaxy.list_active_systems(session)
    Process.send_after(self(), :timeout, 5_000)
    {:noreply, %{state | systems: systems}}
  end

  def handle_info(:timeout, %{session: session, systems: systems} = state) do
    Logger.info("[Galaxy Scanner] Scanning Systems")
    _ = scan_galaxy(session, systems)
    Process.send_after(self(), :timeout, 5_000)
    {:noreply, state}
  end

  def scan_galaxy(session, systems) do
    systems
    |> Task.async_stream(
      fn system ->
        # IO.puts("Scanning #{system.name}")

        with {:ok, system} <- Trekmap.AirDB.create_or_update(system),
             {:ok, {stations, miners}} <-
               Trekmap.Galaxy.System.list_stations_and_miners(system, session),
             {:ok, stations} <- sync_stations(system, stations),
             {:ok, miners} <- sync_miners(system, miners) do
          # IO.puts(
          #   "Scanning #{system.name}: updated #{length(stations)} stations " <>
          #     "and #{length(miners)} miners"
          # )

          {stations, miners}
        else
          other ->
            Logger.error(
              "Error scanning the System #{system.name}, reason: #{inspect(other, pretty: true)}"
            )

            :error
        end
      end,
      max_concurrency: 5,
      timeout: :infinity
    )
    |> Enum.to_list()
  end

  defp sync_stations(system, stations) do
    stations
    |> Enum.reduce_while({:ok, []}, fn station, {status, acc} ->
      with {:ok, player} <- sync_player(station.player),
           planet = %{station.planet | system_external_id: system.external_id},
           {:ok, planet} <- Trekmap.AirDB.create_or_update(planet),
           station = %{station | player: player, planet: planet},
           {:ok, station} <- Trekmap.AirDB.create_or_update(station) do
        station = %{station | player: player, planet: planet, system: system}
        {:cont, {status, [station] ++ acc}}
      else
        error ->
          {:halt, error}
      end
    end)
  end

  defp sync_miners(system, miners) do
    miners
    |> Enum.reduce_while({:ok, []}, fn miner, {status, acc} ->
      with {:ok, player} <- sync_player(miner.player),
           miner = %{miner | player: player},
           {:ok, miner} <- Trekmap.AirDB.create_or_update(miner) do
        miner = %{miner | player: player, system: system}
        {:cont, {status, [miner] ++ acc}}
      else
        error ->
          {:halt, error}
      end
    end)
  end

  defp sync_player(%{alliance: nil} = player) do
    Trekmap.AirDB.create_or_update(player)
  end

  defp sync_player(player) do
    with {:ok, alliance} <- Trekmap.AirDB.create_or_update(player.alliance),
         player = %{player | alliance: alliance},
         {:ok, player} <- Trekmap.AirDB.create_or_update(player) do
      {:ok, %{player | alliance: alliance}}
    end
  end
end
