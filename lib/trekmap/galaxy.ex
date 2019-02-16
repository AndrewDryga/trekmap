defmodule Trekmap.Galaxy do
  alias Trekmap.{APIClient, Session}
  alias Trekmap.Galaxy.System

  @galaxy_nodes_endpoint "https://live-193-web.startrek.digitgaming.com/game_world/galaxy_nodes"
  @scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/quick_multi_scan"

  def list_active_systems(%Session{} = session) do
    additional_headers = Session.session_headers(session)

    with {:ok, %{response: %{"galaxy" => galaxy}}} <-
           APIClient.protobuf_request(:get, @galaxy_nodes_endpoint, additional_headers, "") do
      systems =
        Enum.flat_map(galaxy, fn {_system_bid, system} ->
          %{
            "tree_root" => %{
              "id" => id,
              "attributes" => %{"name" => name, "trans_id" => _transport_id},
              "is_active" => is_active
            }
          } = system

          if is_active do
            [System.build(id, name)]
          else
            []
          end
        end)

      {:ok, systems}
    end
  end

  def scan_players(target_ids, %Session{} = session) do
    body =
      Jason.encode!(%{
        "target_ids" => target_ids,
        "fleet_id" => -1,
        "user_id" => session.account_id,
        "target_type" => 1
      })

    additional_headers = Session.session_headers(session)

    with {:ok, %{response: %{"quick_scan_results" => scan_results}}} <-
           APIClient.protobuf_request(:post, @scanning_endpoint, additional_headers, body) do
      {:ok, scan_results}
    end
  end

  def scan_spaceships(_target_ids, %Session{fleet_id: -1}) do
    raise "fleet_id is not set"
  end

  def scan_spaceships(target_ids, %Session{fleet_id: fleet_id} = session) do
    body =
      Jason.encode!(%{
        "target_ids" => target_ids,
        "fleet_id" => fleet_id,
        "user_id" => session.account_id,
        "target_type" => 0
      })

    additional_headers = Session.session_headers(session)

    with {:ok, %{response: %{"quick_scan_results" => scan_results}}} <-
           APIClient.protobuf_request(:post, @scanning_endpoint, additional_headers, body) do
      {:ok, scan_results}
    else
      {:error, %{body: "scan", type: 2}} -> {:ok, %{"attributes" => %{}}}
      other -> other
    end
  end
end
