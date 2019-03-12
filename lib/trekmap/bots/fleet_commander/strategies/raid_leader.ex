defmodule Trekmap.Bots.FleetCommander.Strategies.RaidLeader do
  alias Trekmap.Galaxy.System.Station
  alias Trekmap.Bots.FleetCommander.Observers.RaidObserver
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, _session) do
    target_station = Keyword.fetch!(config, :target_station)
    {:ok, %{target_station: target_station, station_open?: false, last_strength: nil}}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    {:instant_repair, config}
  end

  def handle_continue(fleet, session, config) do
    %{
      target_station: target_station,
      station_open?: station_open?,
      last_strength: last_strength
    } = config

    name = Trekmap.Bots.FleetCommander.StartshipActor.name(fleet.id)

    with {:ok, station} <- find_station(target_station, session) do
      cond do
        not is_nil(last_strength) and last_strength < station.strength - 100 ->
          Logger.info("[#{name}] Station repaired, aborting")
          RaidObserver.abort(station)
          {:recall, config}

        station_open? ->
          {:recall, config}

        Station.temporary_shield_enabled?(station) ->
          Logger.info("[#{name}] Temporary shield is enabled, waiting")
          {{:wait, 60_000}, config}

        Station.shield_enabled?(station) ->
          Logger.info("[#{name}] Shield is enabled, aborting")
          RaidObserver.abort(station)
          {:recall, config}

        station.hull_health > 2 or station.strength > 20_000 ->
          if station.system.id == fleet.system_id do
            Logger.info("[#{name}] Opening, current strength: #{station.strength}")
            {{:attack, station}, %{config | last_strength: station.strength}}
          else
            {{:fly, station.system, station.coords}, config}
          end

        true ->
          {:recall, %{config | station_open?: true}}
      end
    else
      other ->
        Logger.warn("[#{name}] Station is not found, inspect #{other}")
        RaidObserver.abort(target_station)
        {:recall, config}
    end
  end

  defp find_station(target_station, session) do
    with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(target_station.system, session),
         station when not is_nil(station) <-
           Enum.find(scan.stations, &(&1.id == target_station.id)),
         scan = %{scan | stations: [station], spacecrafts: []},
         {:ok, scan} <- Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session),
         {:ok, scan} <- Trekmap.Galaxy.System.enrich_stations_with_detailed_scan(scan, session) do
      %{stations: [station]} = scan
      {:ok, station}
    end
  end
end
