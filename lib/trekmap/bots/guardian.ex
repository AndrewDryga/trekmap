defmodule Trekmap.Bots.Guardian do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[Guardian] I'm on watch")
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()

    full_repair(session)

    ships_on_mission =
      Trekmap.Bots.FleetCommander.get_ships_on_mission() ++
        Trekmap.Bots.FractionHunter.get_ships_on_mission()

    {:ok, %{session: session, under_attack?: false, ships_on_mission: ships_on_mission}, 0}
  end

  def handle_info(:cancel_attack, state) do
    {:noreply, %{state | under_attack?: false}}
  end

  def handle_info({_ref, _ships_on_mission}, state) do
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    %{session: session, under_attack?: under_attack?, ships_on_mission: ships_on_mission} = state
    {home_fleet, deployed_fleets, defense_stations} = Trekmap.Me.list_ships_and_defences(session)

    ships_at_base =
      home_fleet
      |> Enum.reject(fn ship ->
        Map.has_key?(deployed_fleets, Map.fetch!(ship, "fleet_id"))
      end)
      |> Enum.reject(fn ship ->
        String.to_integer(Map.fetch!(ship, "fleet_id")) in ships_on_mission
      end)

    ships_at_base_alive =
      Enum.reject(ships_at_base, fn ship ->
        Map.fetch!(ship, "damage") == Map.fetch!(ship, "max_hp")
      end)

    base_well_defended? = length(ships_at_base_alive) >= 1

    {fleet_total_health, fleet_total_damage} =
      ships_at_base
      |> Enum.reduce({0, 0}, fn ship, {fleet_total_health, fleet_total_damage} ->
        damage = Map.fetch!(ship, "damage")
        max_hp = Map.fetch!(ship, "max_hp")
        {fleet_total_health + max_hp, fleet_total_damage + damage}
      end)

    fleet_damage_ratio =
      if fleet_total_health == 0, do: 0, else: fleet_total_damage / (fleet_total_health / 100)

    defence_broken? =
      Enum.any?(defense_stations, fn {_id, defense_station} ->
        Map.fetch!(defense_station, "damage") > 100
      end)

    cond do
      fleet_damage_ratio > 95 ->
        Logger.warn("Base broken")
        :ok = Trekmap.Me.activate_shield(session)
        state = stop_mining_hunting(state)
        # state = continue_klingon_hunting(state)
        {:ok, session} = full_repair(session)
        Process.send_after(self(), :timeout, 1)
        {:noreply, %{state | session: session}}

      under_attack? == true ->
        Logger.warn("Base is under continous attack")
        state = stop_mining_hunting(state)
        # state = stop_klingon_hunting(state)
        {:ok, session} = full_repair(session)
        Process.send_after(self(), :timeout, 1)
        {:noreply, %{state | session: session}}

      fleet_damage_ratio > 50 ->
        Logger.warn("Base is damaged, switching to under attack mode")
        {:ok, session} = full_repair(session)
        state = stop_mining_hunting(state)
        # state = stop_klingon_hunting(state)
        Process.send_after(self(), :timeout, 1)
        Process.send_after(self(), :cancel_attack, :timer.minutes(15))
        {:noreply, %{state | session: session, under_attack?: true}}

      defence_broken? == true ->
        Logger.warn("Base defence is damaged, switching to under attack mode")
        {:ok, session} = full_repair(session)
        state = stop_mining_hunting(state)
        # state = stop_klingon_hunting(state)
        Process.send_after(self(), :timeout, 1)
        Process.send_after(self(), :cancel_attack, :timer.minutes(15))
        {:noreply, %{state | session: session, under_attack?: true}}

      not base_well_defended? ->
        Logger.warn("Base is not well defended, do not bait")
        state = continue_mining_hunting(state)
        # state = stop_klingon_hunting(state)
        {:ok, session} = full_repair(session)
        Process.send_after(self(), :timeout, 1)
        {:noreply, %{state | session: session}}

      fleet_damage_ratio > 0 ->
        # state = stop_klingon_hunting(state)
        Logger.info("Baiting, damaged by #{trunc(fleet_damage_ratio)}%")
        Process.send_after(self(), :timeout, 1_000)
        {:noreply, state}

      true ->
        state = continue_mining_hunting(state)
        # state = continue_klingon_hunting(state)
        Process.send_after(self(), :timeout, 1_000)
        {:noreply, state}
    end
  end

  @jellyfish_fleet_id Trekmap.Me.Fleet.jellyfish_fleet_id()
  # @northstar_fleet_id Trekmap.Me.Fleet.northstar_fleet_id()
  @kehra_fleet_id Trekmap.Me.Fleet.kehra_fleet_id()

  defp stop_mining_hunting(%{ships_on_mission: ships_on_mission} = state) do
    Trekmap.Bots.FleetCommander.stop_missions()
    Trekmap.Bots.FleetCommander2.stop_missions()
    %{state | ships_on_mission: ships_on_mission -- [@jellyfish_fleet_id, @kehra_fleet_id]}
  end

  defp continue_mining_hunting(%{ships_on_mission: ships_on_mission} = state) do
    Trekmap.Bots.FleetCommander.continue_missions()
    Trekmap.Bots.FleetCommander2.continue_missions()
    ships_on_mission = Enum.uniq([@jellyfish_fleet_id, @kehra_fleet_id] ++ ships_on_mission)
    %{state | ships_on_mission: ships_on_mission}
  end

  # defp stop_klingon_hunting(%{ships_on_mission: ships_on_mission} = state) do
  #   Trekmap.Bots.FractionHunter.stop_missions()
  #   %{state | ships_on_mission: ships_on_mission -- [@northstar_fleet_id]}
  # end
  #
  # defp continue_klingon_hunting(%{ships_on_mission: ships_on_mission} = state) do
  #   if @northstar_fleet_id in ships_on_mission do
  #     Trekmap.Bots.FractionHunter.continue_missions()
  #     state
  #   else
  #     Trekmap.Bots.FractionHunter.continue_missions()
  #     %{state | ships_on_mission: [@northstar_fleet_id] ++ ships_on_mission}
  #   end
  # end

  defp full_repair(session) do
    with :ok <- Trekmap.Me.full_repair(session) do
      {:ok, session}
    else
      {:error, :session_expired} ->
        {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
        full_repair(session)

      {:error, :timeout} ->
        full_repair(session)
    end
  end
end
