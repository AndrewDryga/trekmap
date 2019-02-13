defmodule Trekmap.Galaxy.System.Station do
  alias Trekmap.{APIClient, Session, Products}
  alias Trekmap.Galaxy.System.Station.{Resources, DetailedScan}

  @behaviour Trekmap.AirDB

  @station_scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/scan_starbase_detailed"

  defstruct id: nil,
            external_id: nil,
            player: nil,
            system: nil,
            planet: nil,
            shield_triggered_at: nil,
            shield_expires_at: nil,
            resources: %Resources{}

  def table_name, do: "Stations"

  def struct_to_record(%__MODULE__{} = station) do
    %{
      id: id,
      player: %{external_id: player_external_id},
      planet: %{external_id: planet_external_id},
      resources: resources,
      shield_triggered_at: shield_triggered_at,
      shield_expires_at: shield_expires_at
    } = station

    %{
      "ID" => to_string(id),
      "Player" => [player_external_id],
      "Planet" => [planet_external_id],
      "Shield Enabled At" => expiry_time(shield_triggered_at),
      "Shield Ends At" => expiry_time(shield_expires_at),
      "Parsteel" => Map.get(resources, :parsteel),
      "Thritanium" => Map.get(resources, :thritanium),
      "Dlithium" => Map.get(resources, :dlithium)
    }
  end

  def record_to_struct(%{"id" => external_id, "fields" => fields}) do
    %{
      "ID" => id,
      "Player" => [player_external_id],
      "Planet" => [planet_external_id],
      "Shield Enabled At" => shield_triggered_at,
      "Shield Ends At" => shield_expires_at
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
      system: :unfetched,
      shield_triggered_at: shield_triggered_at,
      shield_expires_at: shield_expires_at
    }
  end

  defp expiry_time("0001-01-01T00:00:00.000Z"), do: nil
  defp expiry_time(other), do: other

  def get_station_resources(%__MODULE__{} = station, %Session{} = session) do
    body =
      Jason.encode!(%{
        "fleet_id" => -1,
        "target_user_id" => to_string(station.id)
      })

    url = @station_scanning_endpoint
    additional_headers = Session.session_headers(session)

    with {:ok, response} <-
           APIClient.protobuf_request(:post, url, additional_headers, body, DetailedScan) do
      %{response: %{information: %{properties: %{resources: resources}}}} = response

      resources =
        for resource <- resources, into: %{} do
          {Products.resource_name(resource.id), resource.amount}
        end

      {:ok,
       %Resources{
         parsteel: Map.get(resources, "parsteel"),
         thritanium: Map.get(resources, "thritanium"),
         dlithium: Map.get(resources, "dlithium")
       }}
    else
      {:error, %{"code" => 400}} ->
        {:ok, %Resources{}}
    end
  end
end
