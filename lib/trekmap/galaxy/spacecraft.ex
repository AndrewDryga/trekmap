defmodule Trekmap.Galaxy.Spacecraft do
  @scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/quick_multi_scan"
  @translation_endpoint "https://cdn-nv3-live.startrek.digitgaming.com/gateway/v2/translations/prime"
  @alliances_endpoint "https://live-193-web.startrek.digitgaming.com/alliance/get_alliances_public_info"
  @fleet_repair_endpoint "https://live-193-web.startrek.digitgaming.com/fleet/repair"

  defstruct system: nil,
            player: nil,
            fleet_id: nil

  def repair(fleet_id, session) do
    payload = Jason.encode!(%{"fleet_id" => fleet_id})

    {:ok, 200, _headers, body} =
      :hackney.request(:post, @fleet_repair_endpoint, headers(session), payload, [:with_body])

    case Trekmap.get_protobuf_response(body) do
      %{"quick_scan_results" => scan_results} -> scan_results
      _else -> :error
    end
  end

  defp headers(session) do
    Trekmap.request_headers() ++
      [
        {"Accept", "application/x-protobuf"},
        {"Content-Type", "application/x-protobuf"},
        {"X-AUTH-SESSION-ID", session.session_instance_id}
      ]
  end
end
