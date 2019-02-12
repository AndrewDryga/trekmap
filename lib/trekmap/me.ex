defmodule Trekmap.Me do
  alias Trekmap.{APIClient, Session, Job}
  require Logger

  @sync_endpoint "https://live-193-web.startrek.digitgaming.com/sync"
  @fleet_repair_endpoint "https://live-193-web.startrek.digitgaming.com/fleet/repair"

  def full_repair(session) do
    with {{:error, :not_found}, {:error, :not_found}} <- fetch_repair_jobs(session) do
      {home_fleet, _deployed_fleets, _defense_stations} = list_ships_and_defences(session)
      :ok = repair_all_fleet(home_fleet, session)
    else
      {_ship_repair_job, {:ok, station_repair_job}} ->
        :ok = finish_station_repair(station_repair_job, session)
        full_repair(session)

      {{:ok, ship_repair_job}, _station_repair_job} ->
        :ok = finish_fleet_repair(ship_repair_job, session)
        full_repair(session)

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
        end
    end
  end

  def start_fleet_repair(%{"fleet_id" => fleet_id, "damage" => damage}, session) do
    Logger.info("Repairing #{fleet_id} damaged by #{damage}")

    additional_headers = Session.session_headers(session)
    body = Jason.encode!(%{"fleet_id" => binary_to_integer(fleet_id)})

    APIClient.protobuf_request(:post, @fleet_repair_endpoint, additional_headers, body)
    |> case do
      {:error, %{code: 4, response: "fleet"}} ->
        Logger.warn("Ship is already repairing")

        fetch_ship_repair_job(session)
        |> finish_fleet_repair(session)

      {:error, %{code: 14, response: "fleet"}} ->
        Logger.warn("Other ship is already repairing")

        fetch_ship_repair_job(session)
        |> finish_fleet_repair(session)

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
