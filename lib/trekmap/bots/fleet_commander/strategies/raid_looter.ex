defmodule Trekmap.Bots.FleetCommander.Strategies.RaidLooter do
  alias Trekmap.Galaxy.System.Station
  alias Trekmap.Bots.FleetCommander.Observers.RaidObserver
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, _session) do
    target_station = Keyword.fetch!(config, :target_station)
    {:ok, %{target_station: target_station, last_total_resources: nil, killed_times: 0}}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    {:instant_repair, config}
  end

  def handle_continue(%{hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    {:recall, config}
  end

  def handle_continue(%{hull_health: hull_health}, _session, config)
      when hull_health < 5 do
    {:instant_repair, %{config | killed_times: config.killed_times + 1}}
  end

  def handle_continue(%{cargo_size: 0} = fleet, session, config) do
    %{
      target_station: target_station,
      last_total_resources: last_total_resources,
      killed_times: killed_times
    } = config

    name = Trekmap.Bots.FleetCommander.StartshipActor.name(fleet.id)

    # TODO: Handle sitations when somebody is defening station by killing my ships
    with {:ok, station} <- find_station(target_station, session) do
      total_resources =
        station.resources.dlithium + station.resources.parsteel + station.resources.thritanium

      report = %{
        target_station: station,
        looter_action: "Waiting",
        looter_killed_times: killed_times,
        last_loot: last_total_resources
      }

      last_hit_total_resources =
        if is_nil(last_total_resources) do
          0
        else
          last_total_resources - total_resources
        end

      cond do
        killed_times >= 3 ->
          Trekmap.Bots.Admiral.update_raid_report(%{report | looter_action: "Aborting, killed"})
          Logger.info("[#{name}] Got killed for #{killed_times} times, aborting")
          RaidObserver.abort(station)
          {:recall, config}

        not is_nil(last_total_resources) and
            ((5 < last_hit_total_resources and last_hit_total_resources < 100_000) or
               (last_hit_total_resources < 100_000 and total_resources < 800_000)) ->
          Trekmap.Bots.Admiral.update_raid_report(%{report | looter_action: "Aborting, empty"})
          Logger.info("[#{name}] Empty, last hit got #{last_hit_total_resources}, aborting")
          RaidObserver.abort(station)
          {:recall, config}

        station.hull_health > 0 or station.strength > -1 ->
          Trekmap.Bots.Admiral.update_raid_report(%{report | looter_action: "Waiting"})
          Logger.info("[#{name}] Waiting till base opened")
          {:recall, config}

        Station.temporary_shield_enabled?(station) ->
          message = "Temporary shield is enabled, waiting"
          Trekmap.Bots.Admiral.update_raid_report(%{report | looter_action: message})
          Logger.info("[#{name}] #{message}")
          {{:wait, 60_000}, config}

        Station.shield_enabled?(station) ->
          Trekmap.Bots.Admiral.update_raid_report(%{report | looter_action: "Aborting, shielded"})
          Logger.info("[#{name}] Shield is enabled, aborting")
          RaidObserver.abort(station)
          {{:wait, :timer.minutes(10)}, config}

        true ->
          Trekmap.Bots.Admiral.update_raid_report(%{report | looter_action: "Looting"})

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
