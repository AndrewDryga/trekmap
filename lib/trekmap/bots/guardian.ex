defmodule Trekmap.Bots.Guardian do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[Guardian] I'm on watch")
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, %{session: session}, 0}
  end

  def handle_info(:timeout, %{session: session} = state) do
    {home_fleet, deployed_fleets, defense_stations} = Trekmap.Me.list_ships_and_defences(session)

    base_well_defended? = length(home_fleet) - length(Map.keys(deployed_fleets)) > 2

    defence_broken? =
      Enum.any?(defense_stations, fn {_id, defense_station} ->
        Map.fetch!(defense_station, "damage") > 100
      end)

    {fleet_total_health, fleet_total_damage} =
      Enum.reduce(home_fleet, {0, 0}, fn ship, {fleet_total_health, fleet_total_damage} ->
        damage = Map.fetch!(ship, "damage")
        max_hp = Map.fetch!(ship, "max_hp")
        {fleet_total_health + max_hp, fleet_total_damage + damage}
      end)

    fleet_damage_ratio = fleet_total_damage / (fleet_total_health / 100)

    if fleet_damage_ratio > 50 or not base_well_defended? or defence_broken? do
      with :ok <- Trekmap.Me.full_repair(session) do
        Process.send_after(self(), :timeout, 5_000)
        {:noreply, state}
      else
        {:error, :timeout} ->
          {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
          Process.send_after(self(), :timeout, 100)
          {:noreply, %{session: session}}
      end
    else
      if fleet_damage_ratio > 0 do
        Logger.info(
          "Baiting, damaged by #{trunc(fleet_damage_ratio)}%, " <>
            "base has enough ships: #{inspect(base_well_defended?)}, " <>
            "defence stations seriously damaged #{inspect(defence_broken?)}"
        )
      end

      Process.send_after(self(), :timeout, 5_000)
      {:noreply, state}
    end
  end
end
