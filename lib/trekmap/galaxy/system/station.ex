defmodule Trekmap.Galaxy.System.Station do
  alias Trekmap.{APIClient, Session, Products}
  alias Trekmap.Galaxy.System.Station.{Resources, DetailedScan}

  @station_scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/scan_starstation_detailed"

  defstruct player: nil,
            system: nil,
            planet: nil,
            shield_expires_at: nil,
            shield_triggered_at: nil,
            resources: %Resources{}

  def get_station_resources(%__MODULE__{} = station, %Session{} = session) do
    body =
      Jason.encode!(%{
        "fleet_id" => -1,
        "target_user_id" => to_string(station.player.id)
      })

    url = @station_scanning_endpoint
    additional_headers = Session.session_headers(session)

    IO.inspect({:post, url, additional_headers, body, DetailedScan})

    with {:ok, response} <-
           APIClient.protobuf_request(:post, url, additional_headers, body, DetailedScan) do
      %{result: %{information: %{properties: %{resources: resources}}}} = response

      resources =
        for resource <- resources, into: %{} do
          {Products.resource_name(resource.id), resource.amount}
        end

      %Resources{
        parsteel: Map.get(resources, "parsteel"),
        thritanium: Map.get(resources, "thritanium"),
        dlithium: Map.get(resources, "dlithium")
      }
    else
      other ->
        IO.inspect(other)
        raise "err"
        {:ok, %Resources{}}
    end
  end

  # def get_station_resources(%__MODULE__{} = station, %Session{} = session) do
  #   Enum.map(stations, fn station ->
  #     payload =
  #       Jason.encode!(%{
  #         "fleet_id" => -1,
  #         "target_user_id" => station.user_id
  #       })
  #
  #     url = @station_scanning_endpoint
  #
  #     case :hackney.request(:post, url, headers(session), payload, [:with_body]) do
  #       {:ok, 200, _headers, body} ->
  #         case Trekmap.Galaxy.System.Station.DetailedScan.decode(body) do
  #           %{result: %{information: %{properties: %{resources: resources}}}} ->
  #             resources =
  #               resources
  #               |> Enum.map(fn resource ->
  #                 {Trekmap.Products.resource_name(resource.id), resource.amount}
  #               end)
  #               |> Enum.into(%{})
  #
  #             %{
  #               station
  #               | parsteel: Map.get(resources, "parsteel"),
  #                 thritanium: Map.get(resources, "thritanium"),
  #                 dlithium: Map.get(resources, "dlithium")
  #             }
  #
  #           other ->
  #             IO.puts("[station] Can't resolve rss struct: #{inspect(other)}")
  #             station
  #         end
  #
  #       other ->
  #         IO.puts("[station] Can't fetch rss struct: #{inspect(other)}")
  #         station
  #     end
  #   end)
  # end
  #
  # defp headers(session) do
  #   Trekmap.request_headers() ++
  #     [
  #       {"Accept", "application/x-protobuf"},
  #       {"Content-Type", "application/x-protobuf"},
  #       {"X-AUTH-SESSION-ID", session.session_instance_id}
  #     ]
  # end
end
