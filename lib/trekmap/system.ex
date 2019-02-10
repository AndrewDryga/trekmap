defmodule Trekmap.System do
  @game_world_endpoint "https://live-193-web.startrek.digitgaming.com/game_world"
  @system_nodes_endpoint "#{@game_world_endpoint}/system/dynamic_nodes"
  @galaxy_nodes_endpoint "#{@game_world_endpoint}/galaxy_nodes"

  def list_systems(session) do
    {:ok, 200, _headers, body} =
      :hackney.request(:get, @galaxy_nodes_endpoint, headers(session), "", [:with_body])

    %{"galaxy" => galaxy} = body |> Trekmap.raw_binary_to_string() |> Trekmap.protobuf_to_json()

    Enum.flat_map(galaxy, fn {_system_bid, system} ->
      %{
        "tree_root" => %{
          "id" => id,
          "attributes" => %{"name" => name, "trans_id" => trans_id},
          "is_active" => is_active
        }
      } = system

      if is_active do
        [%{id: id, name: name, trans_id: trans_id}]
      else
        []
      end
    end)
  end

  def list_bases(system, session) do
    payload = Jason.encode!(%{system_id: system.id})
    url = @system_nodes_endpoint

    case :hackney.request(:post, url, headers(session), payload, [:with_body]) do
      {:ok, 200, _headers, body} ->
        body = Trekmap.raw_binary_to_string(body)

        if String.contains?(body, "user_authentication") do
          raise "Session expired"
        end

        case Trekmap.protobuf_to_json(body) do
          %{"player_container" => player_container, "mining_slots" => mining_slots} ->
            bases =
              Enum.flat_map(player_container, fn {planet_id, player_base_ids} ->
                player_base_ids
                |> Enum.reject(&(&1 == "None"))
                |> Enum.map(fn player_base_id ->
                  %Trekmap.Base{
                    player_base_id: player_base_id,
                    system_id: system.id,
                    system_tid: system.trans_id,
                    planet_id: planet_id
                  }
                end)
              end)

            miners =
              Enum.flat_map(mining_slots, fn {mining_slot_id, mining_slot} ->

              end)

          _other ->
            []
        end

      {:ok, 500, _headerss, body} ->
        IO.warn(body)
        []
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
