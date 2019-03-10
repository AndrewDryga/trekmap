defmodule Trekmap.Galaxy.System do
  alias Trekmap.{APIClient, Session}
  alias Trekmap.Galaxy
  alias Trekmap.Galaxy.{Spacecraft, Player, Alliances, Alliances.Alliance, Marauder}
  alias Trekmap.Galaxy.System.{Planet, Station}

  defmodule Scan do
    defstruct system: nil,
              raw_result: %{},
              spacecrafts: [],
              stations: [],
              hostiles: []
  end

  @behaviour Trekmap.AirDB

  @system_nodes_endpoint "https://live-193-web.startrek.digitgaming.com/game_world/system/dynamic_nodes"
  @translation_endpoint "https://cdn-nv3-live.startrek.digitgaming.com/gateway/v2/translations/prime"

  defstruct id: nil,
            external_id: nil,
            name: nil,
            fraction: nil,
            level: nil

  def build(id, name) do
    %__MODULE__{
      id: id,
      name: name
    }
  end

  def table_name, do: "Systems"

  def struct_to_record(%__MODULE__{} = system) do
    %{id: id, level: level, name: name, fraction: fraction} = system

    %{"ID" => to_string(id), "Name" => name}
    |> put_if_not_nil("Fraction", fraction)
    |> put_if_not_nil("Level", level)
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{"ID" => id, "Name" => name} = fields

    %__MODULE__{
      id: String.to_integer(id),
      level: Map.get(fields, "Level"),
      name: name,
      fraction: Map.get(fields, "Fraction"),
      external_id: external_id
    }
  end

  defp put_if_not_nil(map, _key, nil), do: map
  defp put_if_not_nil(map, key, value), do: Map.put(map, key, value)

  def scan_system(%__MODULE__{} = system, %Session{} = session) do
    body = Jason.encode!(%{system_id: system.id})
    additional_headers = Session.session_headers(session)

    with {:ok, %{response: response}} <-
           APIClient.protobuf_request(:post, @system_nodes_endpoint, additional_headers, body) do
      %{
        "player_container" => player_container,
        "mining_slots" => mining_slots,
        "deployed_fleets" => deployed_fleets,
        "marauder_quick_scan_data" => marauders
      } = response

      stations = build_stations_list(system, player_container)
      spacecrafts = build_spacecrafts_list(system, mining_slots, deployed_fleets)
      marauders = build_marauders_list(marauders, deployed_fleets, system)

      {:ok,
       %Scan{
         system: system,
         raw_result: response,
         stations: stations,
         spacecrafts: spacecrafts,
         hostiles: marauders
       }}
    else
      {:error, %{body: "deployment", type: 1}} ->
        {:error, :system_not_visited}

      other ->
        other
    end
  end

  def scan_system_by_id(system_id, %Session{} = session) do
    system_id
    |> Trekmap.Me.get_system(session)
    |> scan_system(session)
  end

  def enrich_stations_and_spacecrafts(%Scan{} = scan, %Session{} = session) do
    %{stations: stations, spacecrafts: spacecrafts} = scan

    with {:ok, {stations, spacecrafts}} <-
           enrich_with_scan_info({stations, spacecrafts}, session),
         {:ok, {stations, spacecrafts}} <-
           enrich_with_alliance_info({stations, spacecrafts}, session) do
      {:ok, %{scan | stations: stations, spacecrafts: spacecrafts}}
    end
  end

  def enrich_stations_with_station_resources(%Scan{} = scan, %Session{} = session) do
    %{stations: stations} = scan

    with {:ok, stations} <- enrich_stations_with_resources(stations, session) do
      {:ok, %{scan | stations: stations}}
    end
  end

  def enrich_stations_with_planet_names(%Scan{} = scan, %Session{} = _session) do
    %{stations: stations} = scan

    with {:ok, stations} <- enrich_stations_with_planet_names(stations) do
      {:ok, %{scan | stations: stations}}
    end
  end

  defp build_marauders_list(marauders, deployed_fleets, system) do
    Enum.flat_map(marauders, fn marauder ->
      %{
        "target_fleet_id" => target_fleet_id,
        "faction_id" => faction_id,
        "strength" => strength,
        "ship_levels" => levels
      } = marauder

      level = levels |> Enum.to_list() |> List.first() |> elem(1)

      if marauder_fleet = Map.get(deployed_fleets, to_string(target_fleet_id)) do
        %{"current_coords" => %{"x" => x, "y" => y}} = marauder_fleet

        [
          %Marauder{
            fraction_id: faction_id,
            target_fleet_id: target_fleet_id,
            system: system,
            coords: {x, y},
            strength: strength,
            level: level
          }
        ]
      else
        []
      end
    end)
  end

  defp build_stations_list(system, player_container) do
    Enum.flat_map(player_container, fn {planet_id, station_ids} ->
      station_ids
      |> Enum.reject(&(&1 == "None"))
      |> Enum.map(fn station_id ->
        %Station{
          id: station_id,
          player: nil,
          system: system,
          planet: %Planet{id: planet_id}
        }
      end)
    end)
  end

  defp build_spacecrafts_list(system, mining_slots, deployed_fleets) do
    Enum.flat_map(deployed_fleets, fn {_fleet_binary_id, deployed_fleet} ->
      %{
        "fleet_id" => fleet_id,
        "current_coords" => %{"x" => x, "y" => y},
        "uid" => player_id,
        "type" => type,
        "is_mining" => is_mining
      } = deployed_fleet

      if type == 1 do
        mining_node_id =
          if is_mining do
            Enum.find_value(mining_slots, fn
              {_x_id, [%{"fleet_id" => miner_fleet_id, "id" => id} | _]} ->
                if miner_fleet_id == fleet_id do
                  id
                else
                  nil
                end
            end)
          end

        [
          %Spacecraft{
            player: %Player{id: player_id},
            system: system,
            id: fleet_id,
            mining_node_id: mining_node_id,
            coords: {x, y}
          }
        ]
      else
        []
      end
    end)
  end

  defp enrich_with_scan_info({stations, spacecrafts}, session) do
    station_ids = stations |> Enum.map(& &1.id)
    miner_user_ids = spacecrafts |> Enum.map(& &1.player.id)
    target_ids = Enum.uniq(station_ids ++ miner_user_ids)

    miner_ids = spacecrafts |> Enum.map(& &1.id) |> Enum.uniq()

    with {:ok, user_scan_results} <- Galaxy.scan_players(target_ids, session),
         {:ok, spaceships_scan_results} <- Galaxy.scan_spaceships(miner_ids, session) do
      stations = apply_scan_info_to_stations(stations, user_scan_results)

      spacecrafts =
        apply_scan_info_to_spacecrafts(spacecrafts, user_scan_results, spaceships_scan_results)

      {:ok, {stations, spacecrafts}}
    end
  end

  defp apply_scan_info_to_stations(stations, scan_results) do
    Enum.map(stations, fn station ->
      %{
        "attributes" => %{
          "owner_alliance_id" => alliance_id,
          "owner_level" => level,
          "owner_name" => name,
          "owner_user_id" => player_id,
          "player_shield" => shield
        }
      } = Map.fetch!(scan_results, station.id)

      shield_expires_at =
        case shield do
          %{"expiry_time" => "0001-01-01T00:00:00"} -> nil
          %{"expiry_time" => "0001-01-01T00:00:00.000Z"} -> nil
          %{"expiry_time" => shield_expires_at} -> shield_expires_at
          _other -> nil
        end

      shield_triggered_at =
        case shield do
          %{"triggered_on" => "0001-01-01T00:00:00"} -> nil
          %{"triggered_on" => "0001-01-01T00:00:00.000Z"} -> nil
          %{"triggered_on" => shield_triggered_at} -> shield_triggered_at
          _other -> nil
        end

      shield_triggered_at = if shield_expires_at, do: shield_triggered_at

      alliance = if not is_nil(alliance_id) and alliance_id != 0, do: %Alliance{id: alliance_id}

      %{
        station
        | player: %Player{
            id: player_id,
            alliance: alliance,
            level: level,
            name: name
          },
          shield_expires_at: shield_expires_at,
          shield_triggered_at: shield_triggered_at
      }
    end)
  end

  defp apply_scan_info_to_spacecrafts(spacecrafts, scan_results, spaceships_scan_results) do
    Enum.map(spacecrafts, fn miner ->
      %{
        "attributes" => %{
          "owner_alliance_id" => alliance_id,
          "owner_level" => level,
          "owner_name" => name
        }
      } = Map.fetch!(scan_results, miner.player.id)

      spaceships_attributes =
        Map.get(spaceships_scan_results, to_string(miner.id), %{})["attributes"] || %{}

      alliance =
        if alliance_id do
          %Alliance{id: alliance_id}
        end

      bounty_score =
        if resources = Map.get(spaceships_attributes, "resources") do
          Spacecraft.calculate_bounty_score(resources)
        else
          0
        end

      strength =
        if strength = Map.get(spaceships_attributes, "strength") do
          strength + Map.get(spaceships_attributes, "officer_rating", 0) +
            Map.get(spaceships_attributes, "defense_rating", 0)
        end

      %{
        miner
        | player: %{
            miner.player
            | alliance: alliance,
              level: level,
              name: name
          },
          strength: strength,
          bounty_score: bounty_score
      }
    end)
  end

  def enrich_stations_with_planet_names(stations) do
    planet_ids = Enum.map(stations, & &1.planet.id)
    planet_ids_string = planet_ids |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.join(",")

    url = "#{@translation_endpoint}?language=en&entity=#{planet_ids_string}"

    with {:ok, 200, _headers, body} <- :hackney.request(:get, url, [], "", [:with_body]) do
      %{"translations" => %{"entity" => entities}} = Jason.decode!(body)

      entity_names =
        for entity <- entities, into: %{} do
          {Map.fetch!(entity, "id"), Map.fetch!(entity, "text")}
        end

      stations =
        Enum.map(stations, fn station ->
          if planet_name = Map.get(entity_names, to_string(station.planet.id)) do
            %{station | planet: %{station.planet | name: planet_name}}
          else
            station
          end
        end)

      {:ok, stations}
    end
  end

  def enrich_with_alliance_info({stations, spacecrafts}, session) do
    alliance_ids =
      (stations ++ spacecrafts)
      |> Enum.reject(&is_nil(&1.player.alliance))
      |> Enum.map(& &1.player.alliance.id)
      |> Enum.uniq()

    with {:ok, alliances} <- Alliances.list_alliances_by_ids(alliance_ids, session) do
      stations = apply_alliance_info(stations, alliances)
      spacecrafts = apply_alliance_info(spacecrafts, alliances)
      {:ok, {stations, spacecrafts}}
    end
  end

  defp apply_alliance_info(stations_or_spacecrafts, alliances) do
    Enum.map(stations_or_spacecrafts, fn station_or_miner ->
      if alliance = station_or_miner.player.alliance do
        alliance = Map.get(alliances, alliance.id, alliance)
        %{station_or_miner | player: %{station_or_miner.player | alliance: alliance}}
      else
        station_or_miner
      end
    end)
  end

  def enrich_stations_with_resources(stations, session) do
    Enum.reduce_while(stations, {:ok, []}, fn station, {status, acc} ->
      case Station.get_station_resources(station, session) do
        {:ok, resources} ->
          {:cont, {status, [%{station | resources: resources}] ++ acc}}

        error ->
          {:halt, error}
      end
    end)
  end
end
