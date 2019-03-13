defmodule Trekmap.Bots.GalaxyScanner do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[Galaxy Scanner] Looking for a good hunt")
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, %{session: session, systems: nil}, 0}
  end

  def handle_info(:timeout, %{session: session, systems: nil} = state) do
    Logger.info("[Galaxy Scanner] Scanning Galaxy for first time")
    {:ok, systems} = Trekmap.Galaxy.list_active_systems(session)

    Enum.reduce_while(systems, {:ok, []}, fn system, {status, acc} ->
      with {:ok, system} <- Trekmap.AirDB.create_or_update(system) do
        {:cont, {status, [system] ++ acc}}
      else
        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, systems} ->
        Logger.info("[Galaxy Scanner] #{length(systems)} systems found")

        Process.send_after(self(), :timeout, 1_000)
        {:noreply, %{state | systems: systems}}

      {:error, reason} ->
        Logger.info("[Galaxy Scanner] error persisting systems, #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(:timeout, %{session: session, systems: systems} = state) do
    Logger.info("[Galaxy Scanner] Scanning Systems")
    {:ok, systems} = scan_galaxy(session, systems)
    Process.send_after(self(), :timeout, 5_000)
    {:noreply, %{state | systems: systems}}
  end

  def scan_galaxy(session, systems) do
    systems =
      systems
      |> Enum.shuffle()
      |> Task.async_stream(&scan_and_sync_system(&1, session),
        max_concurrency: 20,
        timeout: :infinity
      )
      |> Enum.flat_map(fn
        {:ok, nil} ->
          Logger.info("Skipping not visited system")
          []

        {:ok, system} ->
          [system]
      end)

    {:ok, systems}
  end

  def scan_and_sync_system(system, session) do
    with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(system, session),
         {:ok, scan} <-
           Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session),
         {:ok, scan} <-
           Trekmap.Galaxy.System.enrich_stations_with_detailed_scan(scan, session),
         stations = scan.stations,
         {:ok, stations} <- sync_stations(system, stations) do
      # {:ok, miners} <- sync_miners(system, miners) do
      Logger.debug(
        "[Galaxy Scanner] Scanning #{system.name}: updated #{length(stations)} stations "
        # <> "and #{length(miners)} miners"
      )

      system
    else
      {:error, :system_not_visited} ->
        nil

      {:error, %{body: "user_authentication", type: 102}} ->
        raise "Session expired"

      other ->
        Logger.error(
          "[Galaxy Scanner] Error scanning the System #{system.name}, " <>
            "reason: #{inspect(other, pretty: true)}"
        )

        system
    end
  end

  defp sync_stations(system, stations) do
    stations
    |> Enum.reduce_while({:ok, []}, fn station, {status, acc} ->
      if station.player.level < 15 do
        {:cont, {status, acc}}
      else
        total_resources =
          (station.resources.dlithium ||
             0) + (station.resources.parsteel || 0) + (station.resources.thritanium || 0)

        if station.strength < 100 and total_resources > 2_000_000 do
          alliance_tag =
            if station.player.alliance, do: "[#{station.player.alliance.tag}] ", else: ""

          ("Found zeroed base #{alliance_tag}#{station.player.name} with #{total_resources} rss, " <>
             "at #{to_string(station.system.name)} / #{to_string(station.planet.name)}" <>
             "cc @AndrewDryga#5388")
          |> Trekmap.Discord.send_message()
        end

        with {:ok, station} <- sync_station(system, station) do
          {:cont, {status, [station] ++ acc}}
        else
          error ->
            {:halt, error}
        end
      end
    end)
  end

  def sync_station(system, station) do
    with {:ok, player} <- sync_player(station.player),
         planet = %{station.planet | system_external_id: system.external_id},
         {:ok, planet} <- Trekmap.AirDB.create_or_update(planet),
         station = %{station | player: player, planet: planet},
         {:ok, station} <- Trekmap.AirDB.create_or_update(station) do
      {:ok, %{station | player: player, planet: planet, system: system}}
    end
  end

  # defp sync_miners(system, miners) do
  #   miners
  #   |> Enum.reduce_while({:ok, []}, fn miner, {status, acc} ->
  #     if miner.player.level < 15 do
  #       {:cont, {status, acc}}
  #     else
  #       with {:ok, player} <- sync_player(miner.player),
  #            miner = %{miner | player: player},
  #            {:ok, miner} <- Trekmap.AirDB.create_or_update(miner) do
  #         miner = %{miner | player: player, system: system}
  #         {:cont, {status, [miner] ++ acc}}
  #       else
  #         error ->
  #           {:halt, error}
  #       end
  #     end
  #   end)
  # end

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
