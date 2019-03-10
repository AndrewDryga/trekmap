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
      "Planet" => [planet_external_id]
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
      system: :unfetched,
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
             parsteel: Map.get(resources, "parsteel"),
             thritanium: Map.get(resources, "thritanium"),
             dlithium: Map.get(resources, "dlithium")
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
end
