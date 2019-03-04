defmodule Trekmap.Bots.FleetCommander.Strategies.StationDefender do
  require Logger

  @behaviour Trekmap.Bots.FleetCommander.Strategy

  def init(_config, _session) do
    {:ok, %{}}
  end

  def handle_continue(%{state: :at_dock}, _session, config) do
    {{:wait, :timer.minutes(60)}, config}
  end

  def handle_continue(_fleet, _session, config) do
    {:recall, config}
  end
end
