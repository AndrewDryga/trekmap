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
              "attributes" => %{"name" => name, "trans_id" => transport_id},
              "is_active" => is_active
            }
          } = system

          if is_active do
            [System.build(id, transport_id, name)]
          else
            []
          end
        end)

      {:ok, systems}
    end
  end

  def scan_targets(target_ids, %Session{} = session) do
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
      # TODO: Resolve into nice structs
      {:ok, scan_results}
    end
  end
end
