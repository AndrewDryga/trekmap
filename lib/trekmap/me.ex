defmodule Trekmap.Me do
  alias Trekmap.{APIClient, Session, Job, Galaxy, Galaxy.Spacecraft}
  alias Trekmap.Me.Fleet
  require Logger

  @sync_endpoint "https://live-193-web.startrek.digitgaming.com/sync"
  @fleet_repair_endpoint "https://live-193-web.startrek.digitgaming.com/fleet/repair"
  @shield_endpoint "https://live-193-web.startrek.digitgaming.com/resources/use_shield_token"
  @fleet_recall_endpoint "https://live-193-web.startrek.digitgaming.com/courses/recall_fleet_warp"
  @fleet_course_endpoint "https://live-193-web.startrek.digitgaming.com/courses/set_fleet_warp_course"

  ## Me

  def get_system(system_id, %Session{} = session) do
    [system] = Graph.vertex_labels(session.galaxy, system_id)
    system
  end

  def get_home_system(%Session{} = session) do
    [system] = Graph.vertex_labels(session.galaxy, session.home_system_id)
    system
  end

  def fetch_current_state(%Session{} = session) do
    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "2"}]

    with {:ok, %{response: response}} <-
           APIClient.protobuf_request(:post, @sync_endpoint, additional_headers, "") do
      %{
        "starbase" => starbase,
        "fleets" => fleets,
        "my_deployed_fleets" => deployed_fleets
      } = response

      {:ok, {starbase, fleets, deployed_fleets}}
    end
  end

  ## Navigation

  def warp_to_system(%Fleet{} = fleet, system_id, %Session{} = session) do
    path = Galaxy.find_path(session.galaxy, fleet.system_id || session.home_system_id, system_id)

    body =
      Jason.encode!(%{
        "target_action" => -1,
        "target_action_id" => 0,
        "fleet_id" => fleet.id,
        "client_warp_path" => path,
        "target_node" => system_id,
        "target_x" => 0,
        "target_y" => 0
      })

    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "2"}]

    with {:ok, %{response: response}} <-
           APIClient.protobuf_request(:post, @fleet_course_endpoint, additional_headers, body) do
      %{"my_deployed_fleets" => deployed_fleets} = response
      fleet_map = Map.fetch!(deployed_fleets, to_string(fleet.id))
      {:ok, %{Fleet.build(fleet_map) | state: :charging, remaining_travel_time: 6}}
    else
      {:error, %{body: "course", type: 2}} -> {:ok, fleet}
      {:error, %{body: "course", type: 6}} -> {:error, :in_warp}
      {:error, %{body: "game_world", type: 1}} -> {:error, :in_warp}
      {:error, %{body: "deployment", type: 5}} -> {:error, :in_warp}
      {:error, %{body: "fleet", type: 9}} -> {:error, :fleet_on_repair}
      {:error, %{body: "course", type: 13}} -> {:error, :invalid_course}
    end
  end

  def fly_to_coords(%Fleet{} = fleet, {x, y}, %Session{} = session) do
    path = [fleet.system_id]

    body =
      Jason.encode!(%{
        "target_action" => -1,
        "target_action_id" => 0,
        "fleet_id" => fleet.id,
        "client_warp_path" => path,
        "target_node" => fleet.system_id,
        "target_x" => x,
        "target_y" => y
      })

    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "2"}]

    with {:ok, %{response: response}} <-
           APIClient.protobuf_request(:post, @fleet_course_endpoint, additional_headers, body) do
      %{"my_deployed_fleets" => deployed_fleets} = response
      fleet_map = Map.fetch!(deployed_fleets, to_string(fleet.id))
      {:ok, Fleet.build(fleet_map)}
    else
      {:error, %{body: "course", type: 2}} -> {:ok, fleet}
      {:error, %{body: "course", type: 6}} -> {:error, :in_warp}
      {:error, %{body: "game_world", type: 1}} -> {:error, :in_warp}
      {:error, %{body: "deployment", type: 5}} -> {:error, :in_warp}
      {:error, %{body: "fleet", type: 9}} -> {:error, :fleet_on_repair}
      {:error, %{body: "fleet", type: 4}} -> {:error, :fleet_on_repair}
      {:error, %{body: "course", type: 13}} -> {:error, :invalid_course}
    end
  end

  def attack_miner(%Fleet{} = fleet, %Spacecraft{} = spacecraft, %Session{} = session) do
    %{coords: {x, y}} = spacecraft
    path = [fleet.system_id]

    body =
      Jason.encode!(%{
        "target_action" => 4,
        "target_action_id" => spacecraft.mining_node_id,
        "fleet_id" => fleet.id,
        "client_warp_path" => path,
        "target_node" => fleet.system_id,
        "target_x" => x,
        "target_y" => y
      })

    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "2"}]

    with false <- shield_enabled?(session),
         {:ok, %{response: response}} <-
           APIClient.protobuf_request(:post, @fleet_course_endpoint, additional_headers, body) do
      %{"my_deployed_fleets" => deployed_fleets} = response
      fleet_map = Map.fetch!(deployed_fleets, to_string(fleet.id))
      {:ok, Fleet.build(fleet_map)}
    else
      true -> {:error, :shield_is_enabled}
      {:error, %{body: "course", type: 2}} -> {:ok, fleet}
      {:error, %{body: "course", type: 6}} -> {:error, :in_warp}
      {:error, %{body: "game_world", type: 1}} -> {:error, :in_warp}
      {:error, %{body: "deployment", type: 5}} -> {:error, :in_warp}
      {:error, %{body: "fleet", type: 9}} -> {:error, :fleet_on_repair}
      {:error, %{body: "fleet", type: 4}} -> {:error, :fleet_on_repair}
      {:error, %{body: "course", type: 13}} -> {:error, :invalid_course}
      {:error, %{"code" => 400}} -> {:error, :invalid_target}
    end
  end

  def recall_fleet(%Fleet{} = fleet, %Session{} = session) do
    path = Galaxy.find_path(session.galaxy, fleet.system_id, session.home_system_id)
    body = Jason.encode!(%{"fleet_id" => fleet.id, "client_warp_path" => path})
    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "2"}]

    with {:ok, %{response: response}} <-
           APIClient.protobuf_request(:post, @fleet_recall_endpoint, additional_headers, body) do
      %{"my_deployed_fleets" => deployed_fleets} = response

      if fleet_map = Map.get(deployed_fleets, to_string(fleet.id)) do
        {:ok, Fleet.build(fleet_map)}
      else
        :ok
      end
    else
      {:error, %{body: "course", type: 2}} -> :ok
      {:error, %{body: "course", type: 6}} -> {:error, :in_warp}
      {:error, %{body: "game_world", type: 1}} -> {:error, :in_warp}
      {:error, %{body: "deployment", type: 5}} -> {:error, :in_warp}
      {:error, %{body: "fleet", type: 9}} -> {:error, :fleet_on_repair}
      {:error, %{body: "course", type: 13}} -> {:error, :invalid_course}
    end
  end

  ## Shield

  def shield_enabled?(%Session{} = session) do
    with {:ok, result} <- Trekmap.Galaxy.scan_players([session.account_id], %Session{} = session) do
      %{
        "attributes" => %{"player_shield" => %{"expiry_time" => shield_expiry_time}}
      } = Map.fetch!(result, to_string(session.account_id))

      NaiveDateTime.compare(
        NaiveDateTime.from_iso8601!(shield_expiry_time),
        NaiveDateTime.utc_now()
      ) == :gt
    end
  end

  def activate_shield(%Session{} = session) do
    if shield_enabled?(session) do
      :ok
    else
      {token, duration} = Trekmap.Products.get_shield_token(1, :hour)
      additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "1"}]

      body =
        Jason.encode!(%{
          "resource_id" => token,
          "target_type" => 1,
          "shield_duration" => duration,
          "user_id" => session.account_id
        })

      with {:ok, %{response: %{"message" => message}}} <-
             APIClient.protobuf_request(:post, @shield_endpoint, additional_headers, body) do
        Logger.info(to_string(message))
        :ok
      end
    end
  end

  ## Repair

  def full_repair(%Session{} = session) do
    with {{:error, :not_found}, {:error, :not_found}} <- fetch_repair_jobs(session) do
      {home_fleet, _deployed_fleets, _defense_stations} = list_ships_and_defences(session)
      :ok = repair_all_fleet(home_fleet, session)
    else
      {{:ok, ship_repair_job}, _station_repair_job} ->
        :ok = finish_fleet_repair(ship_repair_job, session)
        full_repair(session)

      {_ship_repair_job, {:ok, station_repair_job}} ->
        :ok = finish_station_repair(station_repair_job, session)
        full_repair(session)

      {:error, :not_found} ->
        :ok

      {:error, %{body: "user_authentication", type: 102}} ->
        {:error, :session_expired}
    end
  end

  ## Station

  def fetch_repair_jobs(session) do
    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "1"}]
    decoder = APIClient.JsonResponsePrimeSync1

    with {:ok, result} <-
           APIClient.protobuf_request(:post, @sync_endpoint, additional_headers, "", decoder) do
      {Job.fetch_ship_repair_job(result), Job.fetch_station_repair_job(result)}
    else
      {:ok, 413, _headers, _body} ->
        {:error, :not_found}

      other ->
        other
    end
  end

  def fetch_station_repair_job(session) do
    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "1"}]
    decoder = APIClient.JsonResponsePrimeSync1

    with {:ok, result} <-
           APIClient.protobuf_request(:post, @sync_endpoint, additional_headers, "", decoder) do
      Job.fetch_station_repair_job(result)
    end
  end

  def finish_station_repair(%{id: id, remaining_duration: duration}, session) do
    Logger.info("Finishing station repair job #{id} with current duration #{duration}")
    boost_token = Job.Speedup.get_station_repair_token()
    amount = Float.ceil(duration / Job.Speedup.get_station_repair_cost())

    with :ok <- Job.Speedup.boost_job(id, boost_token, amount, session),
         {:error, :not_found} <- fetch_station_repair_job(session) do
      :ok
    else
      {:ok, repair_job} ->
        finish_station_repair(repair_job, session)
    end
  end

  ## Fleet

  def fetch_ship_repair_job(session) do
    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "1"}]
    decoder = APIClient.JsonResponsePrimeSync1

    with {:ok, result} <-
           APIClient.protobuf_request(:post, @sync_endpoint, additional_headers, "", decoder) do
      Job.fetch_ship_repair_job(result)
    else
      {:ok, 413, _headers, _body} ->
        {:error, :not_found}

      other ->
        other
    end
  end

  def list_ships_and_defences(session) do
    additional_headers = Session.session_headers(session) ++ [{"X-PRIME-SYNC", "2"}]

    {:ok, result} = APIClient.protobuf_request(:post, @sync_endpoint, additional_headers, "")

    %{
      response: %{
        "fleets" => fleets,
        "ships" => ships,
        "defenses" => defenses,
        "my_deployed_fleets" => deployed_fleets
      }
    } = result

    home_fleet =
      Enum.map(fleets, fn {fleet_id, info} ->
        %{"ship_ids" => [ship_id | _]} = info

        Map.fetch!(ships, to_string(ship_id))
        |> Map.put("fleet_id", fleet_id)
      end)
      |> Enum.reject(fn ship ->
        Map.has_key?(deployed_fleets, Map.fetch!(ship, "fleet_id"))
      end)

    {home_fleet, deployed_fleets, defenses}
  end

  def repair_all_fleet(home_fleet, session) do
    home_fleet
    |> Enum.filter(fn fleet -> Map.fetch!(fleet, "damage") > 0 end)
    |> Enum.sort_by(fn fleet -> Map.fetch!(fleet, "damage") end, &<=/2)
    |> case do
      [] ->
        :ok

      [fleet | _] ->
        with {:ok, repair_job} <- start_fleet_repair(fleet, session),
             :ok <- finish_fleet_repair(repair_job, session) do
          {home_fleet, _deployed_fleets, _defense_stations} = list_ships_and_defences(session)
          repair_all_fleet(home_fleet, session)
        else
          :ok ->
            {home_fleet, _deployed_fleets, _defense_stations} = list_ships_and_defences(session)
            repair_all_fleet(home_fleet, session)

          {:error, :not_found} ->
            {home_fleet, _deployed_fleets, _defense_stations} = list_ships_and_defences(session)
            repair_all_fleet(home_fleet, session)
        end
    end
  end

  def start_fleet_repair(%{"fleet_id" => fleet_id, "damage" => damage}, session) do
    Logger.info("Repairing #{fleet_id} damaged by #{damage}")

    additional_headers = Session.session_headers(session)
    body = Jason.encode!(%{"fleet_id" => binary_to_integer(fleet_id)})

    APIClient.protobuf_request(:post, @fleet_repair_endpoint, additional_headers, body)
    |> case do
      {:error, %{body: "fleet", type: 4}} ->
        Logger.warn("Ship is already repairing")

        with {:ok, job} <- fetch_ship_repair_job(session) do
          finish_fleet_repair(job, session)
        end

      {:error, %{body: "fleet", type: 14}} ->
        Logger.warn("Other ship is already repairing")

        with {:ok, job} <- fetch_ship_repair_job(session) do
          finish_fleet_repair(job, session)
        end

      :ok ->
        fetch_ship_repair_job(session)
    end
  end

  def finish_fleet_repair(%{id: id, remaining_duration: duration}, session) do
    Logger.info("Finishing repair job #{id} with current duration #{duration}")
    boost_token = Job.Speedup.get_next_ship_repair_token(duration)

    with :ok <- Job.Speedup.boost_job(id, boost_token, session),
         {:error, :not_found} <- fetch_ship_repair_job(session) do
      :ok
    else
      {:ok, repair_job} ->
        finish_fleet_repair(repair_job, session)
    end
  end

  def binary_to_integer(binary) when is_binary(binary), do: String.to_integer(binary)
  def binary_to_integer(number) when is_number(number), do: number
end
