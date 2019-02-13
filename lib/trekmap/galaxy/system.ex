defmodule Trekmap.Galaxy.System do
  alias Trekmap.{APIClient, Session}
  alias Trekmap.Galaxy
  alias Trekmap.Galaxy.{Spacecraft, Player, Alliances, Alliances.Alliance}
  alias Trekmap.Galaxy.System.{Planet, Station}

  @system_nodes_endpoint "https://live-193-web.startrek.digitgaming.com/game_world/system/dynamic_nodes"
  @translation_endpoint "https://cdn-nv3-live.startrek.digitgaming.com/gateway/v2/translations/prime"

  defstruct id: nil,
            transport_id: nil,
            fraction: nil,
            name: nil,
            level: nil

  def build(id, transport_id, name) do
    %{
      build_by_name(name)
      | id: id,
        transport_id: transport_id
    }
  end

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
        {[], []}

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
              fleet_id: fleet_id
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
          %{"expiry_time" => shield_expires_at} -> shield_expires_at
          _other -> nil
        end

      shield_triggered_at =
        case shield do
          %{"expiry_time" => shield_triggered_at} -> shield_triggered_at
          _other -> nil
        end

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

  defp build_by_name("Argrico"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Odal"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Entrunar"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Aetisan"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Maynard"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Wokapa"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Alacti"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Dolcan"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Bridford"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Cecin"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Patton"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Resola"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Taoji"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Nurt"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Lunfa"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Poservoz"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Vinmaier"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Landi"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Calex"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Dyrr"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Kepp"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Hessen"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Pinikou"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Panuq"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Ramexik"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Xoja"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Lockred"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Mulk"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Bohvanderro"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Aoro"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Palimer"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Yridia"), do: %__MODULE__{fraction: "Neutral", level: 7}
  defp build_by_name("Orkon"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Lotch"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("New Sligo"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Rabalon"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Melllvar"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Lanoitan"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Konockt"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Vawur"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Takik"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Injerra"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Lyra"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Vatok"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Klora"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Laxos"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Berebul"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Yerma"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Hroga"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Aker"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Winber"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Worhundelja"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Murasaki 312"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Colt"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Junid"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Dauan"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Zorga"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Obbia"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Delbaana"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Soman"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Wagirur"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Vinland"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Forhingre"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Kito"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Tellun"), do: %__MODULE__{fraction: "Neutral", level: 7}
  defp build_by_name("Donnel"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Jeybriol"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Maq"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Cymon"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Khic"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Muhen"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Wuver"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Falko"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Laurgatt"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Lyquan"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Kerao"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Feer"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Jobe"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Saqua"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Vemarii"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Skelg"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Lasairbheatha"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Baw"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Hosun"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Jinnia"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Sido"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Pimo"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Quirad"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Iora"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Alorina"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Beyven"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Didi"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Mayagrazi"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Ruli"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Flok"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Eravan"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Maluria"), do: %__MODULE__{fraction: "Neutral", level: 7}
  defp build_by_name("Boorhi"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Slawlor"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Reelah"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Bodex"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Lipas"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Nidox"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Poja"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Toshen"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Zukerat"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Zanti"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Tohvus"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Bo-Jeems"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Dalfa"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Soeller"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Barra"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Corla"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Follin"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Benzi"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Melvara"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Volta"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Doma"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Heima"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Halkon"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Cospilon"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Dovaler"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Banks"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Izbel"), do: %__MODULE__{fraction: "Neutral", level: 1}
  defp build_by_name("Groshi"), do: %__MODULE__{fraction: "Neutral", level: 2}
  defp build_by_name("Estrada"), do: %__MODULE__{fraction: "Neutral", level: 4}
  defp build_by_name("Yuvaa"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Eral"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Risa"), do: %__MODULE__{fraction: "Neutral", level: 7}
  defp build_by_name("Littledove"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Lyon"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Iaswo"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Istyna"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Mesadin"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Taleka"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Solusta"), do: %__MODULE__{fraction: "Neutral", level: 7}
  defp build_by_name("Emola"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Veist"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Wretsky"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Gurdy"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Fyufi"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Kroci"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Coth"), do: %__MODULE__{fraction: "Neutral", level: 7}
  defp build_by_name("Fiadh"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Mielikki"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Ulzar"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Cosa"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Mara Eya"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Alonso"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Aindia"), do: %__MODULE__{fraction: "Neutral", level: 7}
  defp build_by_name("Kibuka"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Katonda"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Eshu"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Leza"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Tapio"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Kauko"), do: %__MODULE__{fraction: "Neutral", level: 6}
  defp build_by_name("Boru"), do: %__MODULE__{fraction: "Neutral", level: 7}
  defp build_by_name("Duvlock"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Sual"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Ergantal"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Boniv"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Aodaan"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Maglynn"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Bernin"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Pyr"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Moston"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Súilneimhe"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Cara Alpha"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Cara Beta"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Rosenberg"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Minnea"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Fithis"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Robesi"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Demavar"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Tova"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Zog"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Rua"), do: %__MODULE__{fraction: "Neutral", level: 8}
  defp build_by_name("Grenfil"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Whinnul"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Tynkar"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Mackers"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Doraboro"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Ellijo"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Donfo"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Somaochu"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Ethjamar"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Aum"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Bulut"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Weh"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Elva"), do: %__MODULE__{fraction: "Neutral", level: 11}
  defp build_by_name("Zehoro"), do: %__MODULE__{fraction: "Neutral", level: 11}
  defp build_by_name("Suqigor"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Ceguh"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Uuuuhai"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Nooia"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Utoqa"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Xipox"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Qubas"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Yosiqul"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Benif"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Nilkino"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Flibble"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Liynuk"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Later"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Sohkia"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Fostaa"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Rozi"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Mari"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Luheez"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Dignam"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Imgra"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Yoki Neesh"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Alannah"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Maya"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Dudu"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Honsao"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Gobbo"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Luca"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Una"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Zonu"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Collep"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Quvolis"), do: %__MODULE__{fraction: "Neutral", level: 11}
  defp build_by_name("Eojur"), do: %__MODULE__{fraction: "Neutral", level: 11}
  defp build_by_name("Xabek"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Veias"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Yesop"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Kayojui"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Friefra"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Vogum"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Lodum"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Zozalin"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Xiyia"), do: %__MODULE__{fraction: "Neutral", level: 9}
  defp build_by_name("Zamam"), do: %__MODULE__{fraction: "Neutral", level: 10}
  defp build_by_name("Nelve"), do: %__MODULE__{fraction: "Neutral", level: 12}
  defp build_by_name("Nausicaa"), do: %__MODULE__{fraction: "Neutral", level: 12}
  defp build_by_name("Clytomenes"), do: %__MODULE__{fraction: "Neutral", level: 12}
  defp build_by_name("Orion"), do: %__MODULE__{fraction: "Neutral", level: 12}
  defp build_by_name("Bellas"), do: %__MODULE__{fraction: "Neutral", level: 12}
  defp build_by_name("Rigel"), do: %__MODULE__{fraction: "Neutral", level: 13}
  defp build_by_name("Zaurak"), do: %__MODULE__{fraction: "Neutral", level: 13}
  defp build_by_name("Elona"), do: %__MODULE__{fraction: "Neutral", level: 13}
  defp build_by_name("Astrida"), do: %__MODULE__{fraction: "Neutral", level: 14}
  defp build_by_name("Dhi'Ban"), do: %__MODULE__{fraction: "Neutral", level: 14}
  defp build_by_name("Lycia"), do: %__MODULE__{fraction: "Neutral", level: 14}
  defp build_by_name("Vindemiatrix"), do: %__MODULE__{fraction: "Neutral", level: 15}
  defp build_by_name("Deneva"), do: %__MODULE__{fraction: "Neutral", level: 15}
  defp build_by_name("Cita Laga"), do: %__MODULE__{fraction: "Neutral", level: 15}
  defp build_by_name("Labac"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Obilent"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Rakkaus"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Ocus"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Ione"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Laidcenn"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Araiza"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("H'ganrem"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Amador"), do: %__MODULE__{fraction: "Neutral", level: 19}
  defp build_by_name("Atreig"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Madra"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Medua"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Ragnarr"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Gra"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Dle’greffo"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Midnight"), do: %__MODULE__{fraction: "Neutral", level: 19}
  defp build_by_name("Bharani"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Eizeb"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Aciben"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Vemet"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Wezen"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Bubeau"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Eisenhorn"), do: %__MODULE__{fraction: "Neutral", level: 19}
  defp build_by_name("Zhang"), do: %__MODULE__{fraction: "Neutral", level: 19}
  defp build_by_name("Kepler-018"), do: %__MODULE__{fraction: "Neutral", level: 20}
  defp build_by_name("Fastolf"), do: %__MODULE__{fraction: "Neutral", level: 21}
  defp build_by_name("Jishui"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Kaus Australis"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Kaus Borealis"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Kaus Media"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Helvetios"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Todem"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Wasat"), do: %__MODULE__{fraction: "Neutral", level: 19}
  defp build_by_name("Zeta Polis"), do: %__MODULE__{fraction: "Neutral", level: 19}
  defp build_by_name("Azha"), do: %__MODULE__{fraction: "Neutral", level: 20}
  defp build_by_name("Sorenle"), do: %__MODULE__{fraction: "Neutral", level: 21}
  defp build_by_name("Ora Leraa"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Pune"), do: %__MODULE__{fraction: "Neutral", level: 16}
  defp build_by_name("Freyda"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Oltomon"), do: %__MODULE__{fraction: "Neutral", level: 17}
  defp build_by_name("Dalukerinborva"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Skyedark"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Gelvin"), do: %__MODULE__{fraction: "Neutral", level: 19}
  defp build_by_name("Kosz"), do: %__MODULE__{fraction: "Neutral", level: 19}
  defp build_by_name("Opla"), do: %__MODULE__{fraction: "Neutral", level: 20}
  defp build_by_name("Draken"), do: %__MODULE__{fraction: "Neutral", level: 23}
  defp build_by_name("Afritalis"), do: %__MODULE__{fraction: "Neutral", level: 30}
  defp build_by_name("Willenia"), do: %__MODULE__{fraction: "Neutral", level: 28}
  defp build_by_name("Lorillia"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Kaikara"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Krah'Hor"), do: %__MODULE__{fraction: "Neutral", level: 18}
  defp build_by_name("Voss"), do: %__MODULE__{fraction: "Federation", level: 20}
  defp build_by_name("Lo'Uren Co"), do: %__MODULE__{fraction: "Federation", level: 21}
  defp build_by_name("Aruna"), do: %__MODULE__{fraction: "Federation", level: 21}
  defp build_by_name("Priya"), do: %__MODULE__{fraction: "Federation", level: 22}
  defp build_by_name("Hann"), do: %__MODULE__{fraction: "Federation", level: 22}
  defp build_by_name("Vulcan"), do: %__MODULE__{fraction: "Federation", level: 23}
  defp build_by_name("Earorfiliad"), do: %__MODULE__{fraction: "Federation", level: 24}
  defp build_by_name("Foaiveb"), do: %__MODULE__{fraction: "Federation", level: 23}
  defp build_by_name("Gemet"), do: %__MODULE__{fraction: "Federation", level: 25}
  defp build_by_name("Bazamex"), do: %__MODULE__{fraction: "Federation", level: 24}
  defp build_by_name("Eagutim"), do: %__MODULE__{fraction: "Federation", level: 25}
  defp build_by_name("Doska"), do: %__MODULE__{fraction: "Federation", level: 27}
  defp build_by_name("Mapic"), do: %__MODULE__{fraction: "Federation", level: 25}
  defp build_by_name("P'Jem"), do: %__MODULE__{fraction: "Federation", level: 28}
  defp build_by_name("Metea"), do: %__MODULE__{fraction: "Federation", level: 24}
  defp build_by_name("Iocau"), do: %__MODULE__{fraction: "Federation", level: 22}
  defp build_by_name("Zadiaoo"), do: %__MODULE__{fraction: "Federation", level: 22}
  defp build_by_name("Gowok"), do: %__MODULE__{fraction: "Federation", level: 23}
  defp build_by_name("Thama"), do: %__MODULE__{fraction: "Federation", level: 32}
  defp build_by_name("Noakyn"), do: %__MODULE__{fraction: "Federation", level: 30}
  defp build_by_name("Siiolux"), do: %__MODULE__{fraction: "Federation", level: 35}
  defp build_by_name("Aerimea"), do: %__MODULE__{fraction: "Romulan", level: 35}
  defp build_by_name("Aerie"), do: %__MODULE__{fraction: "Romulan", level: 35}
  defp build_by_name("Aesir"), do: %__MODULE__{fraction: "Romulan", level: 34}
  defp build_by_name("Alatum"), do: %__MODULE__{fraction: "Romulan", level: 43}
  defp build_by_name("Algeron"), do: %__MODULE__{fraction: "Romulan", level: 50}
  defp build_by_name("Alpha Onias"), do: %__MODULE__{fraction: "Romulan", level: 36}
  defp build_by_name("Altanea"), do: %__MODULE__{fraction: "Romulan", level: 38}
  defp build_by_name("Argentomea"), do: %__MODULE__{fraction: "Romulan", level: 35}
  defp build_by_name("Arnab"), do: %__MODULE__{fraction: "Romulan", level: 48}
  defp build_by_name("Baraka"), do: %__MODULE__{fraction: "Romulan", level: 44}
  defp build_by_name("Belak"), do: %__MODULE__{fraction: "Romulan", level: 43}
  defp build_by_name("Biruin"), do: %__MODULE__{fraction: "Romulan", level: 27}
  defp build_by_name("Caerulum"), do: %__MODULE__{fraction: "Romulan", level: 43}
  defp build_by_name("Campus Stellae"), do: %__MODULE__{fraction: "Romulan", level: 47}
  defp build_by_name("Chaltok"), do: %__MODULE__{fraction: "Romulan", level: 42}
  defp build_by_name("Chiron"), do: %__MODULE__{fraction: "Romulan", level: 43}
  defp build_by_name("Cillers"), do: %__MODULE__{fraction: "Romulan", level: 25}
  defp build_by_name("D’Deridex"), do: %__MODULE__{fraction: "Romulan", level: 40}
  defp build_by_name("Dauouuy"), do: %__MODULE__{fraction: "Romulan", level: 22}
  defp build_by_name("Davidul"), do: %__MODULE__{fraction: "Romulan", level: 20}
  defp build_by_name("Dessica"), do: %__MODULE__{fraction: "Romulan", level: 42}
  defp build_by_name("Devoras"), do: %__MODULE__{fraction: "Romulan", level: 42}
  defp build_by_name("Devroe"), do: %__MODULE__{fraction: "Romulan", level: 42}
  defp build_by_name("Eden"), do: %__MODULE__{fraction: "Romulan", level: 40}
  defp build_by_name("Ferraria"), do: %__MODULE__{fraction: "Romulan", level: 45}
  defp build_by_name("Galorndon Core"), do: %__MODULE__{fraction: "Romulan", level: 30}
  defp build_by_name("Garadius"), do: %__MODULE__{fraction: "Romulan", level: 45}
  defp build_by_name("Glintara"), do: %__MODULE__{fraction: "Romulan", level: 43}
  defp build_by_name("Gradientes"), do: %__MODULE__{fraction: "Romulan", level: 30}
  defp build_by_name("Haakona"), do: %__MODULE__{fraction: "Romulan", level: 45}
  defp build_by_name("Huebr"), do: %__MODULE__{fraction: "Romulan", level: 24}
  defp build_by_name("Iota Pavonis"), do: %__MODULE__{fraction: "Romulan", level: 44}
  defp build_by_name("Izanagi"), do: %__MODULE__{fraction: "Romulan", level: 32}
  defp build_by_name("Jaq"), do: %__MODULE__{fraction: "Romulan", level: 30}
  defp build_by_name("Jeuaiei"), do: %__MODULE__{fraction: "Romulan", level: 25}
  defp build_by_name("Kaisu"), do: %__MODULE__{fraction: "Romulan", level: 33}
  defp build_by_name("Khazara"), do: %__MODULE__{fraction: "Romulan", level: 43}
  defp build_by_name("Koltiska"), do: %__MODULE__{fraction: "Romulan", level: 28}
  defp build_by_name("Lapedes"), do: %__MODULE__{fraction: "Romulan", level: 36}
  defp build_by_name("Lempo"), do: %__MODULE__{fraction: "Romulan", level: 31}
  defp build_by_name("Llorrac"), do: %__MODULE__{fraction: "Romulan", level: 21}
  defp build_by_name("Lloyd"), do: %__MODULE__{fraction: "Romulan", level: 30}
  defp build_by_name("Mada"), do: %__MODULE__{fraction: "Romulan", level: 21}
  defp build_by_name("Mewudoh"), do: %__MODULE__{fraction: "Romulan", level: 25}
  defp build_by_name("Nabok"), do: %__MODULE__{fraction: "Romulan", level: 22}
  defp build_by_name("Nasturta"), do: %__MODULE__{fraction: "Romulan", level: 26}
  defp build_by_name("Nelvana"), do: %__MODULE__{fraction: "Romulan", level: 32}
  defp build_by_name("Nequencia"), do: %__MODULE__{fraction: "Romulan", level: 38}
  defp build_by_name("Nipaj"), do: %__MODULE__{fraction: "Romulan", level: 24}
  defp build_by_name("Oppidum Frumenti"), do: %__MODULE__{fraction: "Romulan", level: 30}
  defp build_by_name("Parka"), do: %__MODULE__{fraction: "Romulan", level: 30}
  defp build_by_name("Posel"), do: %__MODULE__{fraction: "Romulan", level: 23}
  defp build_by_name("Rator"), do: %__MODULE__{fraction: "Romulan", level: 29}
  defp build_by_name("Robeton"), do: %__MODULE__{fraction: "Romulan", level: 31}
  defp build_by_name("Romii"), do: %__MODULE__{fraction: "Romulan", level: 40}
  defp build_by_name("Romulus"), do: %__MODULE__{fraction: "Romulan", level: 60}
  defp build_by_name("Rooth"), do: %__MODULE__{fraction: "Romulan", level: 26}
  defp build_by_name("Rosec"), do: %__MODULE__{fraction: "Romulan", level: 22}
  defp build_by_name("Ruxuley"), do: %__MODULE__{fraction: "Romulan", level: 42}
  defp build_by_name("Stagnimea"), do: %__MODULE__{fraction: "Romulan", level: 40}
  defp build_by_name("Strezhi"), do: %__MODULE__{fraction: "Romulan", level: 26}
  defp build_by_name("Sufiday"), do: %__MODULE__{fraction: "Romulan", level: 25}
  defp build_by_name("Tandorian"), do: %__MODULE__{fraction: "Romulan", level: 31}
  defp build_by_name("Terix"), do: %__MODULE__{fraction: "Romulan", level: 38}
  defp build_by_name("Terminimurus"), do: %__MODULE__{fraction: "Romulan", level: 39}
  defp build_by_name("Tillicu"), do: %__MODULE__{fraction: "Romulan", level: 58}
  defp build_by_name("Timore"), do: %__MODULE__{fraction: "Romulan", level: 43}
  defp build_by_name("Tolo"), do: %__MODULE__{fraction: "Romulan", level: 52}
  defp build_by_name("Tufem"), do: %__MODULE__{fraction: "Romulan", level: 23}
  defp build_by_name("Tyee"), do: %__MODULE__{fraction: "Romulan", level: 56}
  defp build_by_name("Umbra Minima"), do: %__MODULE__{fraction: "Romulan", level: 54}
  defp build_by_name("Unrouth"), do: %__MODULE__{fraction: "Romulan", level: 32}
  defp build_by_name("V’varia"), do: %__MODULE__{fraction: "Romulan", level: 21}
  defp build_by_name("Vendor"), do: %__MODULE__{fraction: "Romulan", level: 34}
  defp build_by_name("Vendus A"), do: %__MODULE__{fraction: "Romulan", level: 27}
  defp build_by_name("Wauoxic"), do: %__MODULE__{fraction: "Romulan", level: 24}
  defp build_by_name("Yadalla"), do: %__MODULE__{fraction: "Romulan", level: 42}
  defp build_by_name("Francihk"), do: %__MODULE__{fraction: "Klingon", level: 20}
  defp build_by_name("Antonehk"), do: %__MODULE__{fraction: "Klingon", level: 21}
  defp build_by_name("Maclyyn"), do: %__MODULE__{fraction: "Klingon", level: 22}
  defp build_by_name("Ciara"), do: %__MODULE__{fraction: "Klingon", level: 26}
  defp build_by_name("Phelan"), do: %__MODULE__{fraction: "Klingon", level: 28}
  defp build_by_name("K'amia"), do: %__MODULE__{fraction: "Klingon", level: 24}
  defp build_by_name("Etaoin"), do: %__MODULE__{fraction: "Klingon", level: 25}
  defp build_by_name("Hoeven"), do: %__MODULE__{fraction: "Klingon", level: 27}
  defp build_by_name("Khitomer"), do: %__MODULE__{fraction: "Klingon", level: 23}
  defp build_by_name("Enthra"), do: %__MODULE__{fraction: "Klingon", level: 27}
  defp build_by_name("Yadow"), do: %__MODULE__{fraction: "Klingon", level: 26}
  defp build_by_name("Jonauer"), do: %__MODULE__{fraction: "Klingon", level: 22}
  defp build_by_name("Godui"), do: %__MODULE__{fraction: "Klingon", level: 23}
  defp build_by_name("Vosak"), do: %__MODULE__{fraction: "Klingon", level: 24}
  defp build_by_name("Morska"), do: %__MODULE__{fraction: "Klingon", level: 29}
  defp build_by_name("Oppidum Pulvis"), do: %__MODULE__{fraction: "Neutral", level: 29}
  defp build_by_name("Ias"), do: %__MODULE__{fraction: "Klingon", level: 26}
  defp build_by_name("Le'Onor"), do: %__MODULE__{fraction: "Federation", level: 21}
  defp build_by_name("Xerxes"), do: %__MODULE__{fraction: "Neutral", level: 29}
  defp build_by_name("Uikuv"), do: %__MODULE__{fraction: "Klingon", level: 23}

  # TODO: describe sytems
  defp build_by_name("Pheben"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ossin"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Fafniri"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Gya'han"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Agrico"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Lunev"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ogun"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Lakeside"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Piuioab"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Loiat"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Gallagher"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Guanyin"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Jonsson"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("lainey"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Alves"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Olorun"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Sverlov"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Nurnias"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("S'mtharz"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Nacip"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Woxoxit"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Denobula Triaxa"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Sud'Day JoH"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Lipig"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Barklay"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Iapedes"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Kuat"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Riktor"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Izth"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ayvren"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Fibona"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Terra Nova"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Lixar"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Benzar"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ganalda"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ursva"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Archanis"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Nezha"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ulrich"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("YoDSutlj NaQ"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Dhi'ban"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Balint"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Zizeyab"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Durchman"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ruttle"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Baryn"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Groombridge 34"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Carraya"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Streit"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Beta Penthe"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Tiwoqua"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Emie"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ok'cet"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Elequa"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Nibiq"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("V'varia"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Mat-am"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ty'Gokor"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Altair"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ok'Vak"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Teneebia"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Tojef"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Frakes"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Vanir"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Tejat"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("H'Atoria"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Beta Renner"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Doloran"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Barnard's Star"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Querlz"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Unroth"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("D'Deridex"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ophiuchi"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("New Vulcan"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Dunne"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Nekosa"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Iezat"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Lelas"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Trill"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ebisu"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Schmietainski"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Vurox"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Peliar Zel"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Beta Laeras"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Iekifog"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Bor"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Al-Dafirah"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Aber-rok"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Bolarus"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Tullias"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Quv'lw"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Babel"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Devrom"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Haiuy"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Nitur"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ku Vakh"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Arcturus"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Dietz"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Inari"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Aiselum"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Tegren"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Mok'Tak"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Gorath"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ty'Rall"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Pahvo"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Forseti"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Huff"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Losti"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Eeli"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ouvem"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ieuun"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Aiti"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Duggan"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Nyame"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Koja"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Lanaj"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Fellebia"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Meuee"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Earorfilad"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Wlb'puq"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("BeK"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Mio"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Sol"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Yajoy"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("May'lang"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ascher"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Mempa"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Jiwu'puH"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Cor Caroli"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Sahqooq"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Elzbar"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Kiyu"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Parasum"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Kurlemann"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("No'Mat"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Feqiiep"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Barnwell"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Eckelberry"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Enning"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Roooven"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Lankal"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Deneb"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Burke"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Nivak"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Andoria"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Cheron"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Dogon"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Alpha Centauri"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Diogo"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Gobuoov"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Kre'Tak"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Axanar"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Ain'Tok"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Pktha"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Sirius"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Shi"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Yutuq"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Urcen"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Earokij"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Sarr-um"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Archer"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Azati"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Januu"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Al-Uzfur"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("H’ganrem"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Eayou"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Loaiy"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Shino"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Laija"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Quv Qeb"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Tau Ceti"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Roxeoun"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Skarcadia"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Sarraq"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Boraka"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Sinisser"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Wolf"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("B'Moth"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Para"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Tellar"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Niawillen"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Qian Niu Xing"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Balduk"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Katovug"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Uaracat"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Canchola"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Stawiarski"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Suliban"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Yoruba"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Qu'Vat"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Kronos"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Rene"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Teenax"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Gomes"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("K’amia"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Vega"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Brestant"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Kov Ar'kadan"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Cha'joQDu"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Pekka"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Efsinyn"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Subezac"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Altamid"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Xices"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Kuvrak"), do: %__MODULE__{fraction: nil, level: nil}
  defp build_by_name("Memory Alpha"), do: %__MODULE__{fraction: nil, level: nil}

  defp build_by_name(_other), do: %__MODULE__{fraction: nil, level: nil}
end
