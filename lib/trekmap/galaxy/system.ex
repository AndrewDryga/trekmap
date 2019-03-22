defmodule Trekmap.Galaxy.System do
  alias Trekmap.{APIClient, Session}
  alias Trekmap.Galaxy
  alias Trekmap.Galaxy.{Spacecraft, Player, Alliances, Alliances.Alliance, Marauder}
  alias Trekmap.Galaxy.System.{Planet, Station}

  defmodule Scan do
    defstruct system: nil,
              spacecrafts: [],
              stations: [],
              hostiles: [],
              resources: []
  end

  @behaviour Trekmap.AirDB

  @system_endpoint "https://live-193-web.startrek.digitgaming.com/game_world/system"
  @system_nodes_endpoint "https://live-193-web.startrek.digitgaming.com/game_world/system/dynamic_nodes"

  defstruct id: nil,
            external_id: nil,
            name: nil,
            fraction: nil,
            level: nil,
            resources: []

  def build(id, name) do
    %__MODULE__{
      id: id,
      name: name
    }
  end

  def table_name, do: "Systems"

  def struct_to_record(%__MODULE__{} = system) do
    %{id: id, level: level, name: name, fraction: fraction, resources: resources} = system

    %{"ID" => to_string(id), "Name" => name, "Resources" => resources}
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
      resources: Map.get(fields, "Resources"),
      external_id: external_id
    }
  end

  defp put_if_not_nil(map, _key, nil), do: map
  defp put_if_not_nil(map, key, value), do: Map.put(map, key, value)

  def scan_system(%__MODULE__{} = system, %Session{} = session) do
    body = Jason.encode!(%{system_id: system.id})
    additional_headers = Session.session_headers(session)

    with {:ok, system_response} <-
           APIClient.json_request(:post, @system_endpoint, additional_headers, body),
         {:ok, response} <-
           APIClient.json_request(:post, @system_nodes_endpoint, additional_headers, body) do
      %{
        "player_container" => player_container,
        "mining_slots" => mining_slots,
        "deployed_fleets" => deployed_fleets,
        "marauder_quick_scan_data" => marauders
      } = response

      system_static_children =
        Enum.reduce(system_response["system"]["static_children"], %{}, fn
          {_kind, children}, acc ->
            Map.merge(acc, children)
        end)

      resources = build_resources_list(mining_slots)
      system = %{system | resources: resources}

      stations = build_stations_list(system, player_container, system_static_children)
      spacecrafts = build_spacecrafts_list(system, mining_slots, deployed_fleets)
      marauders = build_marauders_list(marauders, deployed_fleets, system)

      {:ok,
       %Scan{
         system: system,
         stations: stations,
         spacecrafts: spacecrafts,
         hostiles: marauders,
         resources: resources
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

  def enrich_stations_with_detailed_scan(%Scan{} = scan, %Session{} = session) do
    %{stations: stations} = scan

    with {:ok, stations} <- enrich_stations_with_detailed_scan(stations, session) do
      {:ok, %{scan | stations: stations}}
    end
  end

  def enrich_stations_with_detailed_scan(stations, session) do
    Enum.reduce_while(stations, {:ok, []}, fn station, {status, acc} ->
      case Station.scan_station(station, session) do
        {:ok, station} ->
          {:cont, {status, [station] ++ acc}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp build_resources_list(mining_slots) do
    Enum.flat_map(mining_slots, fn {_node_id, [mining_slot | _]} ->
      %{"point_data" => %{"res" => resource_id}} = mining_slot
      [resource_id]
    end)
    |> Enum.uniq()
    |> Enum.map(fn resource_id ->
      {name, _score} = Trekmap.Products.get_resource_name_and_value_score(resource_id)
      name
    end)
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
        {x, y} =
          case marauder_fleet do
            %{
              "current_course" => %{
                "start_x" => sx,
                "start_y" => sy,
                "end_x" => ex,
                "end_y" => ey,
                "start_time" => started_at,
                "duration" => duration
              }
            }
            when not is_nil(sx) and not is_nil(sy) and not is_nil(ex) and not is_nil(ey) ->
              course_progress =
                NaiveDateTime.diff(
                  NaiveDateTime.utc_now(),
                  NaiveDateTime.from_iso8601!(started_at)
                ) / (duration / 100)

              course_progress = Enum.max([1, course_progress])

              {sx + trunc((sx + ex) / course_progress), sy + trunc((sy + ey) / course_progress)}

            %{"current_coords" => %{"x" => x, "y" => y}} ->
              {x, y}
          end

        [
          %Marauder{
            fraction_id: faction_id,
            target_fleet_id: target_fleet_id,
            system: system,
            coords: {x, y},
            strength: strength,
            level: level,
            pursuit_fleet_id: Map.get(marauder_fleet, "pursuit_target_id")
          }
        ]
      else
        []
      end
    end)
  end

  defp build_stations_list(system, player_container, system_static_children) do
    Enum.flat_map(player_container, fn {planet_id, station_ids} ->
      {stations, _index} =
        station_ids
        |> Enum.reduce({[], 0}, fn
          "None", {stations, index} ->
            {stations, index + 1}

          station_id, {stations, index} ->
            string_id = to_string(planet_id)

            %{
              ^string_id => %{
                "tree_node" => %{
                  "attributes" => %{"name" => name},
                  "coords" => %{"x" => x, "y" => y}
                }
              }
            } = system_static_children

            station = %Station{
              id: station_id,
              player: nil,
              system: system,
              planet_slot_index: index,
              coords: station_coords(index, {x, y}),
              planet: %Planet{id: planet_id, name: name, coords: {x, y}}
            }

            {stations ++ [station], index + 1}
        end)

      stations
    end)
  end

  defp station_coords(0, {x, y}), do: {x + 43, y + -35}
  defp station_coords(1, {x, y}), do: {x + 55, y + -5}
  defp station_coords(2, {x, y}), do: {x + -43, y + 35}
  defp station_coords(3, {x, y}), do: {x + -55, y + 5}
  defp station_coords(4, {x, y}), do: {x + 35, y + 43}
  defp station_coords(5, {x, y}), do: {x + 5, y + 55}
  defp station_coords(6, {x, y}), do: {x + -35, y + -43}
  defp station_coords(7, {x, y}), do: {x + -5, y + -55}
  defp station_coords(8, {x, y}), do: {x + 70, y + -57}
  defp station_coords(9, {x, y}), do: {x + 90, y + -8}
  defp station_coords(10, {x, y}), do: {x + -70, y + 57}
  defp station_coords(11, {x, y}), do: {x + -90, y + 8}
  defp station_coords(12, {x, y}), do: {x + 57, y + 70}
  defp station_coords(13, {x, y}), do: {x + 8, y + 90}
  defp station_coords(14, {x, y}), do: {x + -57, y + -70}
  defp station_coords(15, {x, y}), do: {x + -8, y + -90}

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
            coords: {x, y},
            pursuit_fleet_id: Map.get(deployed_fleet, "pursuit_target_id")
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

  def list_prohibited_systems do
    query_params = %{
      "maxRecords" => 100,
      "filterByFormula" => "OR({Prohibited})"
    }

    Trekmap.AirDB.list(__MODULE__, query_params)
  end
end
