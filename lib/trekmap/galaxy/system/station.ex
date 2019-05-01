defmodule Trekmap.Galaxy.System.Station do
  alias Trekmap.{APIClient, Session, Products}
  alias Trekmap.Galaxy.System.Station.{Resources}

  @behaviour Trekmap.AirDB

  @station_scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/scan_starbase_detailed"

  defstruct id: nil,
            external_id: nil,
            player: nil,
            system: nil,
            planet: nil,
            shield_triggered_at: nil,
            shield_expires_at: nil,
            hull_health: 100,
            defense_platform_hull_health: 100,
            strength: nil,
            station_strength: nil,
            coords: {0, 0},
            planet_slot_index: nil,
            resources: %Resources{}

  def table_name, do: "Stations"

  def struct_to_record(%__MODULE__{} = station) do
    %{
      id: id,
      player: %{external_id: player_external_id},
      planet: %{external_id: planet_external_id},
      resources: resources,
      strength: strength,
      station_strength: station_strength,
      hull_health: hull_health,
      defense_platform_hull_health: defense_platform_hull_health,
      shield_triggered_at: shield_triggered_at,
      shield_expires_at: shield_expires_at
    } = station

    %{
      "ID" => to_string(id),
      "Player" => [player_external_id],
      "Planet" => [planet_external_id],
      "Shield Enabled At" => expiry_time(shield_triggered_at),
      "Shield Ends At" => expiry_time(shield_expires_at),
      "Strength" => strength,
      "Station Strength" => station_strength,
      "Station Health" => hull_health,
      "Defence Health" => defense_platform_hull_health,
      "Parsteel" => Map.get(resources, :parsteel),
      "Thritanium" => Map.get(resources, :thritanium),
      "Dlithium" => Map.get(resources, :dlithium),
      "Last Updated At" => DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{
      "ID" => id,
      "Player" => [player_external_id],
      "Planet" => [planet_external_id],
      "System" => [system_external_id],
      "System ID" => system_id
    } = fields

    %__MODULE__{
      id: id,
      external_id: external_id,
      player: {:unfetched, Trekmap.Galaxy.Player, player_external_id},
      planet: {:unfetched, Trekmap.Galaxy.System.Planet, planet_external_id},
      resources: %__MODULE__.Resources{
        parsteel: Map.get(fields, "Parsteel"),
        thritanium: Map.get(fields, "Thritanium"),
        dlithium: Map.get(fields, "Dlithium")
      },
      strength: Map.get(fields, "Strength"),
      station_strength: Map.get(fields, "Station Strength"),
      hull_health: Map.get(fields, "Station Health"),
      defense_platform_hull_health: Map.get(fields, "Defence Health"),
      system: {:unfetched, Trekmap.Galaxy.System, system_external_id, system_id},
      shield_triggered_at: Map.get(fields, "Shield Enabled At"),
      shield_expires_at: Map.get(fields, "Shield Ends At")
    }
  end

  defp expiry_time("0001-01-01T00:00:00"), do: nil
  defp expiry_time("0001-01-01T00:00:00.000Z"), do: nil
  defp expiry_time(other), do: other

  def scan_station(%__MODULE__{} = station, %Session{} = session) do
    body =
      Jason.encode!(%{
        "fleet_id" => -1,
        "target_user_id" => to_string(station.id)
      })

    url = @station_scanning_endpoint
    additional_headers = Session.session_headers(session)

    with {:ok, %{"starbase_detailed_scan" => starbase_detailed_scan}} <-
           APIClient.json_request(:post, url, additional_headers, body) do
      %{
        "current_hp" => current_hp,
        "max_hp" => max_hp,
        "officer_rating" => officer_rating,
        "offense_rating" => offense_rating,
        "defense_rating" => defense_rating,
        "health_rating" => health_rating,
        "defense_platform_fleet" => %{
          "officer_rating" => defense_platform_officer_rating,
          "offense_rating" => defense_platform_offense_rating,
          "defense_rating" => defense_platform_defense_rating,
          "health_rating" => defense_platform_health_rating,
          "ship_dmg" => defense_platform_ship_dmg,
          "ship_hps" => defense_platform_ship_hps
        },
        "defensive_fleets" => defensive_fleets,
        "resources" => resources
      } = starbase_detailed_scan

      hull_health = current_hp / (max_hp / 100)

      station_strength =
        (officer_rating + offense_rating + defense_rating + health_rating) * (hull_health / 100)

      defensive_fleets_strength =
        Enum.reduce(defensive_fleets, 0, fn
          {_id, nil}, acc ->
            acc

          {_id, fleet}, acc ->
            %{
              "officer_rating" => officer_rating,
              "offense_rating" => offense_rating,
              "defense_rating" => defense_rating,
              "health_rating" => health_rating,
              "ship_dmg" => ship_dmg,
              "ship_hps" => ship_hps
            } = fleet

            hull_health = map_to_num(ship_hps)
            hull_damage = map_to_num(ship_dmg)
            hull_health = 100 - Enum.max([0, hull_damage]) / (hull_health / 100)

            strength =
              (officer_rating + offense_rating + defense_rating + health_rating) *
                (hull_health / 100)

            acc + strength
        end)

      defense_platform_hull_health = map_to_num(defense_platform_ship_hps)
      defense_platform_hull_damage = map_to_num(defense_platform_ship_dmg)

      defense_platform_hull_health =
        100 - Enum.max([0, defense_platform_hull_damage]) / (defense_platform_hull_health / 100)

      defensive_platform_strength =
        (defense_platform_officer_rating + defense_platform_offense_rating +
           defense_platform_defense_rating + defense_platform_health_rating) *
          (defense_platform_hull_health / 100)

      resources =
        for {id, amount} <- resources, into: %{} do
          {Products.resource_name(String.to_integer(id)), amount}
        end

      {:ok,
       %{
         station
         | resources: %Resources{
             parsteel: Map.get(resources, "parsteel", 0),
             thritanium: Map.get(resources, "thritanium", 0),
             dlithium: Map.get(resources, "dlithium", 0)
           },
           hull_health: hull_health,
           defense_platform_hull_health: defense_platform_hull_health,
           station_strength: station_strength + defensive_platform_strength,
           strength: station_strength + defensive_fleets_strength + defensive_platform_strength
       }}
    else
      {:error, %{"code" => 400}} ->
        {:ok, station}
    end
  end

  defp map_to_num(map) do
    map
    |> Enum.map(&elem(&1, 1))
    |> Enum.sum()
  end

  def find_station(user_id) do
    with {:ok, station} <- Trekmap.AirDB.fetch_by_id(__MODULE__, user_id) do
      station = Trekmap.AirDB.preload(station, [:system, :player])
      {:ok, station}
    end
  end

  def fetch_raid_target(session) do
    formula =
      "AND(" <>
        "{Relation} != 'Ally', " <>
        "{Relation} != 'NAP', " <>
        "{Relation} != 'NSA', " <>
        "{In Prohibited System} = 0," <>
        "{Shield Enabled Ago} >= 21600, " <>
        "{Shield Ends In} <= '600', " <>
        "{Last Updated} <= '10800', " <>
        "OR(" <>
        "AND(" <>
        "{Total Weighted} >= '3000000'," <>
        "19 <= {Level}, {Level} <= 23, " <>
        "{Strength} <= 240000" <>
        ")," <>
        "AND(" <>
        "{Total Weighted} >= '800000', " <>
        "19 <= {Level}, {Level} <= 25, " <>
        "{Strength} <= 300000, " <>
        "{System} = #{session.home_system_id}" <>
        ")" <>
        "))"

    query_params = %{
      "maxRecords" => 10,
      "filterByFormula" => formula,
      "sort[0][field]" => "Profitability",
      "sort[0][direction]" => "desc"
    }

    with {:ok, targets} when targets != [] <- Trekmap.AirDB.list(__MODULE__, query_params) do
      target =
        targets
        |> Enum.map(&Trekmap.AirDB.preload(&1, :system))
        |> Enum.sort_by(fn station ->
          path =
            Trekmap.Galaxy.find_path(session.galaxy, session.home_system_id, station.system.id)

          Trekmap.Galaxy.get_path_distance(session.galaxy, path)
        end)
        |> List.first()
        |> Trekmap.AirDB.preload(:player)

      {:ok, target}
    else
      {:ok, []} -> {:error, :not_found}
    end
  end

  def list_system_ids_with_enemy_stations(session) do
    formula = "{Relation} = 'Enemy'"

    query_params = %{
      "maxRecords" => 250,
      "filterByFormula" => formula,
      "sort[0][field]" => "Profitability",
      "sort[0][direction]" => "desc"
    }

    with {:ok, targets} when targets != [] <- Trekmap.AirDB.list(__MODULE__, query_params) do
      target =
        targets
        |> Enum.map(&Trekmap.AirDB.preload(&1, :system))
        |> Enum.sort_by(fn station ->
          path =
            Trekmap.Galaxy.find_path(session.galaxy, session.home_system_id, station.system.id)

          Trekmap.Galaxy.get_path_distance(session.galaxy, path)
        end)
        |> Enum.map(& &1.system.id)
        |> Enum.uniq()

      {:ok, target}
    else
      {:ok, []} -> {:error, :not_found}
    end
  end

  def temporary_shield_enabled?(%__MODULE__{shield_expires_at: nil}) do
    false
  end

  def temporary_shield_enabled?(%__MODULE__{} = station) do
    diff =
      NaiveDateTime.diff(
        NaiveDateTime.from_iso8601!(station.shield_expires_at),
        NaiveDateTime.utc_now()
      )

    0 <= diff and diff <= 600
  end

  def shield_enabled?(%__MODULE__{shield_expires_at: nil}) do
    false
  end

  def shield_enabled?(%__MODULE__{} = station) do
    NaiveDateTime.compare(
      NaiveDateTime.from_iso8601!(station.shield_expires_at),
      NaiveDateTime.utc_now()
    ) != :lt
  end
end
