defmodule Trekmap.Galaxy.System.Station do
  alias Trekmap.{APIClient, Session, Products}
  alias Trekmap.Galaxy.System.Station.{Resources, DetailedScan}

  @station_scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/scan_starbase_detailed"

  defstruct id: nil,
            player: nil,
            system: nil,
            planet: nil,
            shield_triggered_at: nil,
            shield_expires_at: nil,
            resources: %Resources{}

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
