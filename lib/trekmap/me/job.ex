defmodule Trekmap.Job do
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
