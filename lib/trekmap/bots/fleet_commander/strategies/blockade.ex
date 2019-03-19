defmodule Trekmap.Bots.FleetCommander.Strategies.Blockade do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(config, _session) do
    target_station = Keyword.fetch!(config, :target_station)

    {:ok,
     %{
       system: target_station.system,
       target_player_id: target_station.id
     }}
  end

  def handle_continue(%{state: :at_dock, hull_health: hull_health}, _session, config)
      when hull_health < 100 do
    {:instant_repair, config}
  end

  def handle_continue(%{state: :at_dock} = fleet, session, config) do
    {:ok, target_stations, target_spacecrafts} =
      find_targets_in_target_system(fleet, session, config)

    cond do
      length(target_stations) > 0 ->
        station = List.first(target_stations)
        {{:fly, station.system, station.coords}, config}

      length(target_spacecrafts) > 0 ->
        target = Enum.random(target_spacecrafts)
        {{:attack, target}, config}

      true ->
        {{:wait, :timer.seconds(5)}, config}
    end
  end

  def handle_continue(fleet, session, config) do
    {:ok, target_stations, target_spacecrafts} =
      find_targets_in_target_system(fleet, session, config)

    cond do
      length(target_spacecrafts) > 0 ->
        target = Enum.random(target_spacecrafts)
        {{:attack, target}, config}

      length(target_stations) > 0 ->
        station = List.first(target_stations)

        if fleet.coords == station.coords do
          {{:wait, 50}, config}
        else
          {{:fly, station.system, station.coords}, config}
        end

      true ->
        {{:wait, 50}, config}
    end
  end

  defp find_targets_in_target_system(fleet, session, config) do
    %{target_player_id: target_player_id, system: system} = config

    with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(system, session),
         {:ok, %{spacecrafts: spacecrafts, stations: stations}} <-
           Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session) do
      target_stations =
        Enum.filter(stations, fn station -> station.player.id == target_player_id end)

      target_spacecrafts =
        Enum.filter(spacecrafts, fn spacecraft -> spacecraft.player.id == target_player_id end)

      {:ok, target_stations, target_spacecrafts}
    else
      {:error, %{"code" => 400}} = error ->
        Logger.error("Can't list targets in system #{inspect(system)}, reason: #{inspect(error)}")
        :timer.sleep(5_000)
        find_targets_in_target_system(fleet, session, config)
    end
  end
end
