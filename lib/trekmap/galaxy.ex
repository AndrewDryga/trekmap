defmodule Trekmap.Galaxy do
  alias Trekmap.{APIClient, Session}
  alias Trekmap.Galaxy.System

  @galaxy_nodes_endpoint "https://live-193-web.startrek.digitgaming.com/game_world/galaxy_nodes"
  @scanning_endpoint "https://live-193-web.startrek.digitgaming.com/scanning/quick_multi_scan"

  def list_active_systems(%Session{} = session) do
    additional_headers = Session.session_headers(session)

    with {:ok, %{"galaxy" => galaxy}} <-
           APIClient.json_request(:get, @galaxy_nodes_endpoint, additional_headers, "") do
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

    with {:ok, %{"galaxy" => galaxy}} <-
           APIClient.json_request(:get, @galaxy_nodes_endpoint, additional_headers, "") do
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

    with {:ok, %{"quick_scan_results" => scan_results}} <-
           APIClient.json_request(:post, @scanning_endpoint, additional_headers, body) do
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

    with {:ok, %{"quick_scan_results" => scan_results}} <-
           APIClient.json_request(:post, @scanning_endpoint, additional_headers, body) do
      {:ok, scan_results}
    else
      {:error, %{body: "scan", type: 2}} -> {:ok, %{"attributes" => %{}}}
      other -> other
    end
  end

  def fetch_hunting_system_ids!(opts \\ []) do
    grade = Keyword.get(opts, :grade, "***")
    skip_enemy_systems? = Keyword.get(opts, :skip) == :enemy_starship_locations

    target_system_ids =
      if skip_enemy_systems? do
        []
      else
        {:ok, target_system_ids} = list_systems_with_target_startships()
        target_system_ids
      end

    {:ok, mining_system_ids} = list_systems_with_valuable_resouces(grade)

    Enum.uniq(target_system_ids ++ mining_system_ids)
  end

  def list_systems_with_enemy_stations do
    formula =
      "AND(" <>
        "{In Prohibited System} = 0," <>
        "OR(" <>
        "AND(" <>
        "{Relation} != 'Ally', " <>
        "{Relation} != 'NAP', " <>
        "{Relation} != 'NSA', " <>
        "{Total Weighted} >= '15000000'," <>
        "19 <= {Level}, {Level} <= 26, " <>
        "{Strength} <= 500000" <>
        ")," <>
        "{Relation} = 'Enemy'" <>
        "))"

    query_params = %{
      "maxRecords" => 500,
      "filterByFormula" => formula,
      "sort[0][field]" => "Profitability",
      "sort[0][direction]" => "desc"
    }

    with {:ok, targets} when targets != [] <-
           Trekmap.AirDB.list(Trekmap.Galaxy.System.Station, query_params) do
      system_ids =
        targets
        |> Enum.map(fn %{system: {:unfetched, _, _, system_id}} ->
          String.to_integer(system_id)
        end)
        |> Enum.group_by(& &1)
        |> Enum.map(fn {id, entries} -> {id, length(entries)} end)

      {:ok, system_ids}
    end
  end

  def list_systems_with_target_startships do
    formula =
      "AND(" <>
        "{Relation} != 'Ally', " <>
        "{Relation} != 'NAP', " <>
        "{In Prohibited System} = 0," <>
        "{Last Updated} <= '3600', " <>
        "OR({Bounty Score} > 0, {Relation} = 'Enemy')" <>
        ")"

    query_params = %{
      "maxRecords" => 500,
      "filterByFormula" => formula,
      "sort[0][field]" => "Bounty Score",
      "sort[0][direction]" => "desc"
    }

    with {:ok, targets} when targets != [] <-
           Trekmap.AirDB.list(Trekmap.Galaxy.Spacecraft, query_params) do
      system_ids =
        targets
        |> Enum.map(fn %{system: {:unfetched, _, _, system_id}} ->
          String.to_integer(system_id)
        end)
        |> Enum.uniq()

      {:ok, system_ids}
    end
  end

  def list_systems_with_valuable_resouces(grade \\ "**") do
    formula = "SEARCH(\"#{grade}\", {Resources})"

    query_params = %{
      "maxRecords" => 500,
      "filterByFormula" => formula
    }

    with {:ok, systems} when systems != [] <-
           Trekmap.AirDB.list(Trekmap.Galaxy.System, query_params) do
      system_ids =
        systems
        |> Enum.map(& &1.id)
        |> Enum.uniq()

      {:ok, system_ids}
    end
  end

  def list_systems_for_faction(faction, min_system_level \\ nil) do
    formula =
      if min_system_level do
        "AND({Fraction} = '#{faction}', {Level} > #{min_system_level})"
      else
        "{Fraction} = '#{faction}'"
      end

    query_params = %{
      "maxRecords" => 200,
      "filterByFormula" => formula
    }

    with {:ok, systems} when systems != [] <-
           Trekmap.AirDB.list(Trekmap.Galaxy.System, query_params) do
      system_ids =
        systems
        |> Enum.map(& &1.id)
        |> Enum.uniq()

      {:ok, system_ids}
    end
  end

  def list_mining_systems(grade \\ "***") do
    formula = "AND({Fraction} != 'Klingon', SEARCH(\"#{grade}\", {Resources}))"

    query_params = %{
      "maxRecords" => 200,
      "filterByFormula" => formula
    }

    with {:ok, systems} when systems != [] <-
           Trekmap.AirDB.list(Trekmap.Galaxy.System, query_params) do
      system_ids =
        systems
        |> Enum.map(& &1.id)
        |> Enum.uniq()

      {:ok, system_ids}
    end
  end
end
