defmodule Trekmap.Galaxy.System do
  alias Trekmap.{APIClient, Session}
  alias Trekmap.Galaxy
  alias Trekmap.Galaxy.{Spacecraft, Player, Alliances, Alliances.Alliance}
  alias Trekmap.Galaxy.System.{Planet, Station}

  @behaviour Trekmap.AirDB

  @system_nodes_endpoint "https://live-193-web.startrek.digitgaming.com/game_world/system/dynamic_nodes"
  @translation_endpoint "https://cdn-nv3-live.startrek.digitgaming.com/gateway/v2/translations/prime"

  defstruct id: nil,
            external_id: nil,
            transport_id: nil,
            name: nil,
            fraction: nil,
            level: nil

  def build(id, transport_id, name) do
    %__MODULE__{
      id: id,
      name: name,
      transport_id: transport_id
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

  def list_stations_and_miners(%__MODULE__{} = system, %Session{} = session) do
    body = Jason.encode!(%{system_id: system.id})
    additional_headers = Session.session_headers(session)

    with {:ok, %{response: response}} <-
           APIClient.protobuf_request(:post, @system_nodes_endpoint, additional_headers, body),
         %{"player_container" => player_container, "mining_slots" => mining_slots} = response,
         stations = build_stations_list(system, player_container),
         miners = build_miners_list(system, mining_slots),
         {:ok, stations} <- enrich_stations_with_planet_names(stations),
         {:ok, {stations, miners}} <- enrich_with_scan_info({stations, miners}, session),
         {:ok, {stations, miners}} <- enrich_with_alliance_info({stations, miners}, session),
         {:ok, stations} <- enrich_with_resources(stations, session) do
      {:ok, {stations, miners}}
    else
      {:error, %{body: "deployment", type: 1}} ->
        # System is not visited
        {:ok, {[], []}}

      {:error, :session_expired} ->
        {:error, :session_expired}
    end
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

  defp build_miners_list(system, mining_slots) do
    Enum.flat_map(mining_slots, fn {_mining_slot_id, mining_nodes} ->
      case List.first(mining_nodes) do
        %{"is_occupied" => true, "user_id" => player_id, "fleet_id" => fleet_id} ->
          [
            %Spacecraft{
              player: %Player{id: player_id},
              system: system,
              id: fleet_id
            }
          ]

        %{"is_occupied" => false} ->
          []
      end
    end)
  end

  defp enrich_with_scan_info({stations, miners}, session) do
    station_ids = stations |> Enum.map(& &1.id)
    miner_ids = miners |> Enum.map(& &1.player.id)
    target_ids = Enum.uniq(station_ids ++ miner_ids)

    with {:ok, scan_results} <- Galaxy.scan_targets(target_ids, session) do
      stations = apply_scan_info_to_stations(stations, scan_results)
      miners = apply_scan_info_to_miners(miners, scan_results)
      {:ok, {stations, miners}}
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

  defp apply_scan_info_to_miners(stations, scan_results) do
    Enum.map(stations, fn station ->
      %{
        "attributes" => %{
          "owner_alliance_id" => alliance_id,
          "owner_level" => level,
          "owner_name" => name
        }
      } = Map.fetch!(scan_results, station.player.id)

      alliance = if alliance_id, do: %Alliance{id: alliance_id}

      %{
        station
        | player: %{
            station.player
            | alliance: alliance,
              level: level,
              name: name
          }
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

  def enrich_with_alliance_info({stations, miners}, session) do
    alliance_ids =
      (stations ++ miners)
      |> Enum.reject(&is_nil(&1.player.alliance))
      |> Enum.map(& &1.player.alliance.id)
      |> Enum.uniq()

    with {:ok, alliances} <- Alliances.list_alliances_by_ids(alliance_ids, session) do
      stations = apply_alliance_info(stations, alliances)
      miners = apply_alliance_info(miners, alliances)
      {:ok, {stations, miners}}
    end
  end

  defp apply_alliance_info(stations_or_miners, alliances) do
    Enum.map(stations_or_miners, fn station_or_miner ->
      if alliance = station_or_miner.player.alliance do
        alliance = Map.get(alliances, alliance.id, alliance)
        %{station_or_miner | player: %{station_or_miner.player | alliance: alliance}}
      else
        station_or_miner
      end
    end)
  end

  def enrich_with_resources(stations, session) do
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
