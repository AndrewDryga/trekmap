defmodule Trekmap.Me.Job.Speedup do
  alias Trekmap.{APIClient, Session}
  require Logger

  @free_speedup_job_endpoint "https://live-193-web.startrek.digitgaming.com/jobs/speedup_job"
  @paid_speedup_job_endpoint "https://live-193-web.startrek.digitgaming.com/jobs/speedup_job_allow_tokens"
  @buy_resources_endpoint "https://live-193-web.startrek.digitgaming.com/resources/buy_resources"

  @free_speedup_limit 300

  @free_ship_repair_token_id 4_272_690_020
  @free_ship_repair_token {@free_speedup_limit, 0, @free_ship_repair_token_id}

  # Thritanium token which is used to repair base after attacks
  @free_station_repair_token_id 743_985_951
  @free_station_repair_token {@free_speedup_limit, 0, @free_station_repair_token_id}

  @paid_repair_tokens [
    {60, 2, 1_445_265_330},
    {180, 3, 3_019_850_922},
    {300, 5, 1_827_073_923},
    {900, 8, 821_696_896},
    {3600, 15, 3_586_919_025}
  ]

  def get_station_repair_token do
    @free_station_repair_token
  end

  def get_station_repair_cost do
    30
  end

  def get_next_ship_repair_token(repair_duration) do
    if repair_duration <= 300 do
      @free_ship_repair_token
    else
      paid_repair_duration = repair_duration - 300
      get_next_paid_ship_repair_token(paid_repair_duration)
    end
  end

  defp get_next_paid_ship_repair_token(paid_repair_duration) do
    @paid_repair_tokens
    |> Enum.sort_by(fn {duration, cost, _id} ->
      tokens_needed = Float.ceil(paid_repair_duration / duration)
      tokens_needed * cost
    end)
    |> List.first()
  end

  def boost_job(job_id, @free_station_repair_token, amount, session) do
    amount = trunc(amount)
    Logger.info("Using Thritanium repair token to boost station repair #{job_id}, #{amount}")

    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "job_id" => job_id,
        "expected_cost" => [%{"Key" => @free_station_repair_token_id, "Value" => amount}]
      })

    with {:ok, _resp} <-
           APIClient.json_request(:post, @free_speedup_job_endpoint, additional_headers, body) do
      :ok
    end
  end

  def boost_job(job_id, @free_ship_repair_token, session) do
    Logger.info("Using free repair token to boost ship repair #{job_id}")

    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "job_id" => job_id,
        "expected_cost" => [%{"Key" => @free_ship_repair_token_id, "Value" => 0}]
      })

    with {:ok, _resp} <-
           APIClient.json_request(:post, @free_speedup_job_endpoint, additional_headers, body) do
      :ok
    end
  end

  def boost_job(job_id, {duration, _cost, id} = token, session) do
    Logger.debug("Using custom repair token to boost ship repair #{job_id}, #{inspect(token)}")
    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "job_id" => job_id,
        "expected_cost" => [%{"Key" => id, "Value" => 1}],
        "time_reduction" => duration
      })

    with {:ok, _resp} <-
           APIClient.json_request(:post, @paid_speedup_job_endpoint, additional_headers, body) do
      Logger.info("Using paid repair token for #{duration} seconds to boost ship job #{job_id}")
      :ok
    else
      {:error, %{"code" => 400}} ->
        :ok

      {:error, %{body: "resources", type: 1}} ->
        :ok = buy_resources(id, session)
        boost_job(job_id, token, session)

      {:error, %{body: "resources", type: 2}} ->
        :ok = buy_resources(id, session)
        boost_job(job_id, token, session)
    end
  end

  defp buy_resources(resource_id, session) do
    Logger.info("Purchasing additional repair token ID #{resource_id}")

    additional_headers = Session.session_headers(session)

    body =
      Jason.encode!(%{
        "resource_dicts" => [%{"resource_id" => resource_id, "amount" => 1}]
      })

    APIClient.json_request(:post, @buy_resources_endpoint, additional_headers, body)
  end
end
