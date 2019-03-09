defmodule Trekmap.Me.Job do
  alias Trekmap.{APIClient, Session}

  @alliance_help_jobs_list_endpoint "https://live-193-web.startrek.digitgaming.com/alliance/get_job_help_info"
  @alliance_help_jobs_endpoint "https://live-193-web.startrek.digitgaming.com/alliance/help_with_user_jobs"

  def help_all(%Session{} = session) do
    additional_headers = Session.session_headers(session)

    with {:ok, %{response: %{"alliance_job_help_info" => help_info}}} <-
           APIClient.protobuf_request(
             :post,
             @alliance_help_jobs_list_endpoint,
             additional_headers,
             "{}"
           ) do
      help_info =
        Enum.flat_map(help_info, fn
          {job_id, %{"helping_user_ids" => helping_user_ids, "user_id" => user_id}} ->
            if session.account_id not in helping_user_ids and session.account_id != user_id do
              [job_id]
            else
              []
            end
        end)

      payload = Jason.encode!(%{"alliance_id" => 0, "job_ids" => help_info})

      {:ok, _response} =
        APIClient.protobuf_request(
          :post,
          @alliance_help_jobs_endpoint,
          additional_headers,
          payload
        )

      :ok
    end
  end

  def fetch_ship_repair_job(%{active_jobs: %{list: %{items: jobs}}, current_timestamp: cur_ts}) do
    case Enum.filter(jobs, fn item -> Map.fetch!(item, :kind) == 5 end) do
      [job | _jobs] ->
        remaining_duration = remaining_duration(job, cur_ts)

        if remaining_duration > 0 do
          {:ok, %{job | remaining_duration: remaining_duration}}
        else
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def fetch_station_repair_job(%{active_jobs: %{list: %{items: jobs}}, current_timestamp: cur_ts}) do
    case Enum.filter(jobs, fn item -> Map.fetch!(item, :kind) == 7 end) do
      [job | _jobs] ->
        remaining_duration = remaining_duration(job, cur_ts)

        if remaining_duration > 0 do
          {:ok, %{job | remaining_duration: remaining_duration}}
        else
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp remaining_duration(%{duration: 0}, _cur_ts) do
    0
  end

  defp remaining_duration(
         %{duration: duration, start_timestamp: %{value: start_timestamp_value}},
         %{value: cur_ts_value}
       ) do
    duration - (cur_ts_value - start_timestamp_value)
  end
end
