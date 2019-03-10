defmodule Trekmap.Bots.HiveScanner do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, allies} = Trekmap.Galaxy.Alliances.list_allies()
    {:ok, enemies} = Trekmap.Galaxy.Alliances.list_enemies()
    {:ok, kos} = Trekmap.Galaxy.Alliances.list_kos_in_hive()
    hive_system = Trekmap.Me.get_system(session.hive_system_id, session)

    allies = Enum.map(allies, & &1.tag)
    enemies = Enum.map(enemies, & &1.tag)
    kos = Enum.map(kos, & &1.tag)

    {:ok,
     %{
       hive_system: hive_system,
       session: session,
       allies: allies,
       enemies: enemies,
       kos: kos,
       last_scan: nil
     }, 0}
  end

  def handle_info(:timeout, %{last_scan: nil} = state) do
    %{hive_system: hive_system, session: session} = state

    scan =
      with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(hive_system, session),
           {:ok, scan} <- Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session) do
        scan
      else
        _other -> nil
      end

    Process.send_after(self(), :timeout, 5_000)
    {:noreply, %{state | last_scan: scan}}
  end

  def handle_info(:timeout, state) do
    %{
      hive_system: hive_system,
      session: session,
      allies: allies,
      enemies: enemies,
      kos: kos,
      last_scan: last_scan
    } = state

    scan =
      with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(hive_system, session),
           {:ok, scan} <- Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session) do
        build_delta(scan.spacecrafts, last_scan.spacecrafts)
        |> Enum.map(fn {action, spacecraft} ->
          cond do
            ally?(spacecraft, allies) ->
              :ok

            enemy?(spacecraft, enemies) ->
              ("**Enemy** #{player_name(spacecraft)} #{startship_action(action)} " <>
                 "at #{location(spacecraft)}. @everyone")
              |> Trekmap.Discord.send_message()

            kos?(spacecraft, kos) ->
              ("**KOS** #{player_name(spacecraft)} #{startship_action(action)} " <>
                 "at #{location(spacecraft)}. @everyone")
              |> Trekmap.Discord.send_message()

            true ->
              ("Neutral #{player_name(spacecraft)} #{startship_action(action)} " <>
                 "at #{location(spacecraft)}")
              |> Trekmap.Discord.send_message()
          end
        end)

        build_delta(scan.stations, last_scan.stations)
        |> Enum.map(fn {action, station} ->
          cond do
            ally?(station, allies) ->
              "Ally #{player_name(station)} #{station_action(action)} at #{location(station)}"
              |> Trekmap.Discord.send_message()

            enemy?(station, enemies) ->
              ("**Enemy** #{player_name(station)} #{station_action(action)} " <>
                 "at #{location(station)}. @everyone")
              |> Trekmap.Discord.send_message()

            kos?(station, kos) ->
              ("**KOS** #{player_name(station)} #{station_action(action)} " <>
                 "at #{location(station)}. @everyone")
              |> Trekmap.Discord.send_message()

            true ->
              "Neutral #{player_name(station)} #{station_action(action)} at #{location(station)}"
              |> Trekmap.Discord.send_message()
          end
        end)

        scan
      else
        _other ->
          state.last_scan
      end

    Process.send_after(self(), :timeout, 5_000)
    {:noreply, %{state | last_scan: scan}}
  end

  defp station_action(:add), do: "moved station to hive"
  defp station_action(:remove), do: "moved station out of hive"

  defp startship_action(:add), do: "entered system"
  defp startship_action(:remove), do: "is not in the hive system any more"

  defp player_name(%{player: player}) do
    alliance_tag = if player.alliance, do: "[#{player.alliance.tag}] ", else: ""
    "#{alliance_tag}#{player.name}"
  end

  defp location(%{system: system, coords: {x, y}}) do
    "[S:#{system.id} X:#{x} Y:#{y}]"
  end

  defp location(%{system: system, planet: planet}) do
    "[S:#{system.id}] Planet #{planet.name}"
  end

  defp enemy?(station_or_spacecraft, enemies) do
    if station_or_spacecraft.player.alliance,
      do: station_or_spacecraft.player.alliance.tag in enemies,
      else: false
  end

  defp ally?(station_or_spacecraft, allies) do
    if station_or_spacecraft.player.alliance,
      do: station_or_spacecraft.player.alliance.tag in allies,
      else: false
  end

  defp kos?(station_or_spacecraft, kos) do
    if station_or_spacecraft.player.alliance,
      do: station_or_spacecraft.player.alliance.tag in kos,
      else: false
  end

  defp build_delta(current, prev) do
    current_ids = Enum.map(current, & &1.id)
    prev_ids = Enum.map(prev, & &1.id)

    added =
      Enum.map(current_ids -- prev_ids, fn added_id ->
        {:add, Enum.find(current, &(&1.id == added_id))}
      end)

    removed =
      Enum.map(prev_ids -- current_ids, fn removed_id ->
        {:remove, Enum.find(prev, &(&1.id == removed_id))}
      end)

    added ++ removed
  end
end
