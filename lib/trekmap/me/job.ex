defmodule Trekmap.Job do
  # TODO: add remaining duration to job
  def fetch_ship_repair_job(%{active_jobs: %{list: %{items: jobs}}, current_timestamp: cur_ts}) do
    case Enum.filter(jobs, fn item -> Map.fetch!(item, :kind) == 5 end) do
      [job] ->
        remaining_duration = job.duration - (cur_ts.value - job.start_timestamp.value)
        {:ok, %{job | remaining_duration: remaining_duration}}

      [] ->
        {:error, :not_found}
    end
  end

  def fetch_station_repair_job(%{active_jobs: %{list: %{items: jobs}}, current_timestamp: cur_ts}) do
    case Enum.filter(jobs, fn item -> Map.fetch!(item, :kind) == 7 end) do
      [job] ->
        remaining_duration = job.duration - (cur_ts.value - job.start_timestamp.value)
        {:ok, %{job | remaining_duration: remaining_duration}}

      [] ->
        {:error, :not_found}
    end
  end
end
