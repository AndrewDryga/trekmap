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
    {:ok, bad_people} = Trekmap.Galaxy.Player.list_bad_people()
    hive_systems = Enum.map(session.hive_system_ids, &Trekmap.Me.get_system(&1, session))

    allies = Enum.map(allies, & &1.tag)
    enemies = Enum.map(enemies, & &1.tag)
    kos = Enum.map(kos, & &1.tag)
    bad_people_ids = Enum.map(bad_people, & &1.id)

    {:ok,
     %{
       hive_systems: hive_systems,
       session: session,
       allies: allies,
       enemies: enemies,
       bad_people_ids: bad_people_ids,
       kos: kos,
       last_scans: [],
       under_attack: []
     }, :timer.minutes(1)}
  end

  def handle_info(:timeout, %{last_scans: []} = state) do
    %{hive_systems: hive_systems, session: session} = state

    scans = scan_hive_systems(hive_systems, session)

    Process.send_after(self(), :timeout, 5_000)
    {:noreply, %{state | last_scans: scans}}
  end

  def handle_info(:timeout, state) do
    %{
      hive_systems: hive_systems,
      session: session,
      last_scans: last_scans,
      under_attack: under_attack
    } = state

    {last_scans, under_attack} =
      scan_hive_systems(hive_systems, session)
      |> Enum.reduce({[], under_attack}, fn scan, {last_scans_acc, under_attack_acc} ->
        last_scan =
          Enum.find(last_scans, fn last_scan -> last_scan.system.id == scan.system.id end)

        currently_under_attack = report_scan_result(scan, last_scan, under_attack_acc, state)
        {last_scans_acc ++ [scan], Enum.uniq(under_attack_acc ++ currently_under_attack)}
      end)

    Process.send_after(self(), :timeout, 5_000)
    {:noreply, %{state | last_scans: last_scans, under_attack: under_attack}}
  end

  defp scan_hive_systems(systems, session) do
    Enum.flat_map(systems, fn system ->
      with {:ok, scan} <- Trekmap.Galaxy.System.scan_system(system, session),
           {:ok, scan} <- Trekmap.Galaxy.System.enrich_stations_and_spacecrafts(scan, session) do
        [scan]
      else
        _other -> []
      end
    end)
  end

  defp report_scan_result(scan, last_scan, under_attack, state) do
    %{
      allies: allies,
      enemies: enemies,
      kos: kos,
      bad_people_ids: bad_people_ids
    } = state

    build_delta(scan.spacecrafts, last_scan.spacecrafts)
    |> Enum.map(fn {action, spacecraft} ->
      cond do
        ally?(spacecraft, allies) ->
          :ok

        enemy?(spacecraft, enemies) ->
          ("**Enemy #{player_name(spacecraft)} #{startship_action(action, spacecraft)}**. " <>
             "@everyone")
          |> Trekmap.Discord.send_message()

        kos?(spacecraft, kos) or bad_guy?(spacecraft, bad_people_ids) ->
          ("**KOS #{player_name(spacecraft)} #{startship_action(action, spacecraft)}**. " <>
             "@everyone")
          |> Trekmap.Discord.send_message()

        true ->
          "Neutral #{player_name(spacecraft)} #{startship_action(action, spacecraft)}"
          |> Trekmap.Discord.send_message()
      end
    end)

    under_attack =
      scan.stations
      |> Enum.flat_map(fn station ->
        cond do
          ally?(station, allies) and station.id in under_attack ->
            [station.id]

          ally?(station, allies) and station.hull_health < 80 ->
            ("**Ally station IS UNDER ATTACK #{player_name(station)} at #{location(station)}**. " <>
               "@everyone")
            |> Trekmap.Discord.send_message()

            [station.id]

          true ->
            []
        end
      end)

    build_delta(scan.stations, last_scan.stations)
    |> Enum.map(fn {action, station} ->
      cond do
        ally?(station, allies) ->
          "Ally #{player_name(station)} #{station_action(action, station)}"
          |> Trekmap.Discord.send_message()

        enemy?(station, enemies) ->
          "**Enemy #{player_name(station)} #{station_action(action, station)}**. @everyone"
          |> Trekmap.Discord.send_message()

        kos?(station, kos) or bad_guy?(station, bad_people_ids) ->
          "**KOS #{player_name(station)} #{station_action(action, station)}**. @everyone"
          |> Trekmap.Discord.send_message()

        true ->
          "Neutral #{player_name(station)} #{station_action(action, station)}."
          |> Trekmap.Discord.send_message()
      end
    end)

    under_attack
  end

  defp station_action(:add, station), do: "moved station to hive at #{location(station)}"
  defp station_action(:remove, station), do: "moved station out of hive at #{location(station)}"

  defp startship_action(:add, startship), do: "entered system at #{location(startship)}"
  defp startship_action(:remove, _startship), do: "is not in the hive system any more"

  defp player_name(%{player: player}) do
    alliance_tag = if player.alliance, do: "[#{player.alliance.tag}] ", else: ""
    "#{alliance_tag}#{player.name} lvl #{player.level}"
  end

  defp location(%{system: system, coords: {x, y}}) do
    "`[S:#{system.id} X:#{x} Y:#{y}]`"
  end

  defp location(%{system: system, planet: planet}) do
    "`[S:#{system.id}]` planet #{planet.name}"
  end

  defp bad_guy?(station_or_spacecraft, bad_people_ids) do
    station_or_spacecraft.player.id in bad_people_ids
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
    prev_ids = if prev, do: Enum.map(prev, & &1.id), else: []

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
