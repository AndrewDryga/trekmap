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

  def build_systems_graph(session) do
    additional_headers = Session.session_headers(session)

    with {:ok, %{response: %{"galaxy" => galaxy}}} <-
           APIClient.protobuf_request(:get, @galaxy_nodes_endpoint, additional_headers, "") do
      graph =
        Enum.reduce(galaxy, Graph.new(), fn {_system_bid, system}, graph ->
          %{
            "tree_root" => %{
              "id" => id,
              "attributes" => %{"name" => name, "trans_id" => _transport_id},
              "is_active" => is_active
            },
            "connections" => connections
          } = system

          if is_active do
            graph =
              graph
              |> Graph.add_vertex(id)
              |> Graph.label_vertex(id, System.build(id, name))

            Enum.reduce(connections, graph, fn {_id, connection}, graph ->
              %{
                "from_system_id" => from,
                "to_system_id" => to,
                "distance" => distance
              } = connection

              graph
              |> Graph.add_edge(from, to, weight: distance)
              |> Graph.add_edge(to, from, weight: distance)
            end)
          else
            graph
          end
        end)

      {:ok, graph}
    end
  end

  def reject_long_warp_edges(graph, max_warp_distance) do
    Graph.edges(graph)
    |> Enum.reject(&(&1.weight < max_warp_distance))
    |> Enum.reduce(graph, fn edge, graph ->
      Graph.delete_edge(graph, edge.v1, edge.v2)
    end)
  end

  def find_path(_graph, system_id, system_id), do: [system_id]

  def find_path(graph, system_id1, system_id2) do
    if path = Graph.get_shortest_path(graph, system_id1, system_id2) do
      path
    else
      :error
    end
  end

  def get_path_distance(graph, path) do
    {initial_point, rest_path} = List.pop_at(path, 0)

    {_node, distance} =
      Enum.reduce(rest_path, {initial_point, 0}, fn vertex, {prev_vertex, acc} ->
        [%{weight: weight}] = Graph.edges(graph, prev_vertex, vertex)
        {vertex, acc + weight}
      end)

    distance
  end

  def get_path_max_warp_distance(graph, path) do
    {initial_point, rest_path} = List.pop_at(path, 0)

    {_node, max_warp_distance} =
      Enum.reduce(rest_path, {initial_point, 0}, fn vertex, {prev_vertex, acc} ->
        [%{weight: weight}] = Graph.edges(graph, prev_vertex, vertex)
        {vertex, Enum.max([acc, weight])}
      end)

    max_warp_distance
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

  def list_system_ids_with_g2_g3_resources do
    [
      # Dlith,
      958_423_648,
      1_017_582_787,
      218_039_082,
      # 2** raw
      81250,
      83345,
      81459,
      81497,
      81286,
      81354,
      601_072_182,
      1_854_874_708,
      1_718_038_036,
      849_541_812,
      1_790_049_115,
      1_462_287_177,
      1_083_794_899,
      1_490_914_183,
      1_745_143_614,
      1_203_174_739,
      959_318_428,
      # 3** raw
      830_770_182,
      1_133_522_720,
      2_102_605_227,
      1_747_858_074,
      625_581_925,
      186_798_495,
      1_691_252_927,
      717_782_925,
      955_177_926,
      739_609_161,
      1_744_652_289
    ]
    |> Enum.uniq()
  end

  def list_system_ids_with_g3_resources do
    [
      # 3** raw long warp
      955_177_926,
      717_782_925,
      1_016_428_829,
      579_218_493,
      468_245_102,
      516_359_977,
      634_286_176
    ]
    |> Enum.uniq()
  end
end
