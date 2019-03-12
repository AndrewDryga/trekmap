defmodule Trekmap.Bots.FleetCommander.Strategies.RaidLooter do
  alias Trekmap.Galaxy.System.Station
  alias Trekmap.Bots.FleetCommander.Observers.RaidObserver
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, _session) do
    target_station = Keyword.fetch!(config, :target_station)
    {:ok, %{target_station: target_station, last_total_resources: nil}}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    {:instant_repair, config}
  end

  def handle_continue(%{hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    {:recall, config}
  end

  def handle_continue(%{cargo_size: 0} = fleet, session, config) do
    %{target_station: target_station, last_total_resources: last_total_resources} = config

    name = Trekmap.Bots.FleetCommander.StartshipActor.name(fleet.id)

    # TODO: Handle sitations when somebody is defening station by killing my ships
    with {:ok, station} <- find_station(target_station, session) do
      total_resources =
        station.resources.dlithium + station.resources.parsteel + station.resources.thritanium

      cond do
        not is_nil(last_total_resources) and
          last_total_resources - total_resources < 30_000 and
            total_resources < 300_000 ->
          diff = last_total_resources - total_resources
          Logger.info("[#{name}] Empty, last hit got #{diff}, aborting")
          RaidObserver.abort(station)
          {:recall, config}

        station.hull_health > 2 or station.strength > 20_000 ->
          Logger.info("[#{name}] Waiting till base opened")
          {:recall, config}

        Station.temporary_shield_enabled?(station) ->
          Logger.info("[#{name}] Temporary shield is enabled, waiting")
          {{:wait, 60_000}, config}

        Station.shield_enabled?(station) ->
          Logger.info("[#{name}] Shield is enabled, aborting")
          RaidObserver.abort(station)
          {{:wait, :timer.minutes(10)}, config}

        true ->
          if station.system.id == fleet.system_id do
            Logger.info("[#{name}] Looting, station has: #{total_resources}")
            {{:attack, station}, %{config | last_total_resources: total_resources}}
          else
            {{:fly, station.system, station.coords}, config}
          end
      end
    else
      other ->
        Logger.warn("[#{name}] Station is not found, inspect #{other}")
        RaidObserver.abort(target_station)
        {:recall, config}
    end
  end

  def handle_continue(%{cargo_size: cargo_size}, _session, config) when cargo_size > 0 do
    {:recall, config}
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
