defmodule Trekmap.Me.Job do
  alias Trekmap.{APIClient, Session}

  defstruct [:id, :job_type, :duration, :remaining_duration]

  @alliance_help_jobs_list_endpoint "https://live-193-web.startrek.digitgaming.com/alliance/get_job_help_info"
  @alliance_help_jobs_endpoint "https://live-193-web.startrek.digitgaming.com/alliance/help_with_user_jobs"

  def help_all(%Session{} = session) do
    additional_headers = Session.session_headers(session)

    with {:ok, %{"alliance_job_help_info" => help_info}} <-
           APIClient.json_request(
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
        APIClient.json_request(
          :post,
          @alliance_help_jobs_endpoint,
          additional_headers,
          payload
        )

      :ok
    end
  end

  def fetch_ship_repair_job(jobs, server_time) do
    case Enum.filter(jobs, fn job -> Map.fetch!(job, "job_type") == 5 end) do
      [job | _jobs] ->
        %{"duration" => duration, "UUID" => id} = job
        remaining_duration = remaining_duration(job, server_time)

        if remaining_duration > 0 do
          {:ok, %__MODULE__{id: id, duration: duration, remaining_duration: remaining_duration}}
        else
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def fetch_station_repair_job(jobs, server_time) do
    case Enum.filter(jobs, fn job -> Map.fetch!(job, "job_type") == 7 end) do
      [job | _jobs] ->
        %{"duration" => duration, "UUID" => id} = job
        remaining_duration = remaining_duration(job, server_time)

        if remaining_duration > 0 do
          {:ok, %__MODULE__{id: id, duration: duration, remaining_duration: remaining_duration}}
        else
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp remaining_duration(%{"duration" => 0}, _server_time) do
    0
  end

  defp remaining_duration(%{"duration" => duration, "start_time" => start_time}, server_time) do
    start_time = NaiveDateTime.from_iso8601!(start_time)
    server_time = NaiveDateTime.from_iso8601!(server_time)
    duration - NaiveDateTime.diff(server_time, start_time)
  end
end
