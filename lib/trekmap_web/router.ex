defmodule Trekmap.Router do
  use Plug.Router

  plug(:fetch_query_params)
  # plug(Plug.Logger)

  plug(BasicAuth, use_config: {:trekmap, :auth})

  plug(:match)
  plug(:dispatch)

  get "/" do
    {active?, status, ships_on_mission} =
      case Trekmap.Bots.get_status() do
        :running ->
          %{
            under_attack?: under_attack?,
            shield_enabled?: shield_enabled?,
            fleet_damage_ratio: fleet_damage_ratio
          } = Trekmap.Bots.Admiral.get_station_report()

          under_attack = if under_attack?, do: " / Under Attack", else: ""
          shield_enabled = if shield_enabled?, do: " / Shielded", else: ""

          ships_on_mission =
            Trekmap.Bots.Admiral.get_fleet_reports()
            |> Enum.flat_map(fn
              %{
                strategy: strategy,
                mission_paused: mission_paused,
                clearence_granted: clearence_granted,
                system: %{name: system_name},
                fleet: %{
                  state: state,
                  ship_id: ship_id,
                  hull_health: hull_health,
                  cargo_size: cargo_size,
                  remaining_travel_time: remaining_travel_time,
                  cargo_bay_size: cargo_bay_size
                },
                updated_at: updated_at
              } ->
                task_name =
                  case strategy do
                    Trekmap.Bots.FleetCommander.Strategies.StationDefender -> "Defending Station"
                    Trekmap.Bots.FleetCommander.Strategies.HiveDefender -> "Defending Hive"
                    Trekmap.Bots.FleetCommander.Strategies.MinerHunter -> "Hunting Miners"
                    Trekmap.Bots.FleetCommander.Strategies.Miner -> "Miner"
                    Trekmap.Bots.FleetCommander.Strategies.FractionHunter -> "Hunting Hostiles"
                    Trekmap.Bots.FleetCommander.Strategies.RaidLooter -> "Looting Station"
                    Trekmap.Bots.FleetCommander.Strategies.RaidLeader -> "Opening Station"
                    Trekmap.Bots.FleetCommander.Strategies.Punisher -> "Punisher"
                    Trekmap.Bots.FleetCommander.Strategies.Blockade -> "Blockade"
                    other -> inspect(other)
                  end

                ship_name = Trekmap.Me.Fleet.ship_name(ship_id)

                mission_paused = if mission_paused, do: "; PAUSED", else: ""

                clearence_granted =
                  if clearence_granted, do: "", else: "; <b>WAITING FOR CLEARENCE</b>"

                remaining_travel_time =
                  if remaining_travel_time > 0 do
                    arrives_at = DateTime.add(updated_at, remaining_travel_time, :second)
                    format_time(DateTime.diff(arrives_at, DateTime.utc_now(), :second)) <> " "
                  end

                [
                  " - #{ship_name}: #{task_name} #{inspect(state)} #{remaining_travel_time}" <>
                    "at #{system_name} (H:#{trunc(hull_health || 100)}%; " <>
                    "C:#{trunc(cargo_size || 0)}/#{trunc(cargo_bay_size || 0)}" <>
                    "#{mission_paused}#{clearence_granted})"
                ]
            end)
            |> Enum.join(",</br> ")

          {true,
           "Running#{under_attack}#{shield_enabled} / Damaged #{trunc(fleet_damage_ratio)}%",
           ships_on_mission}

        :starting ->
          {false, "Starting", ""}

        {:scheduled, timeout} ->
          minutes = trunc(timeout / 60)
          seconds = rem(timeout, 60) |> to_string() |> String.pad_leading(2, "0")
          {false, "Would start in #{minutes}:#{seconds}", ""}
      end

    raid_mission =
      with true <- active?,
           %{target_station: target} = report <- Trekmap.Bots.Admiral.get_raid_report() do
        alliance_tag = if target.player.alliance, do: "[#{target.player.alliance.tag}] ", else: ""

        total_resources =
          (target.resources.dlithium || 0) +
            (target.resources.parsteel || 0) +
            (target.resources.thritanium || 0)

        last_loot = (Map.get(report, :last_loot) || total_resources) - total_resources

        total_resources =
          total_resources
          |> to_string()
          |> String.graphemes()
          |> Enum.reverse()
          |> Enum.map_every(3, &(&1 <> " "))
          |> Enum.reverse()
          |> Enum.join()

        """
        Raiding #{alliance_tag}#{target.player.name} #{target.player.level} (#{target.id})
        at #{to_string(target.system.name)} / #{to_string(target.planet.name)}<br/>
        Strength: #{target.strength}<br/>
        Resources: #{total_resources} / Last Loot: #{last_loot}<br/>
        <br/>
        Leader: #{Map.get(report, :leader_action, "not active")}<br/>
        Looter: #{Map.get(report, :looter_action, "not active")} / \
        Killed #{Map.get(report, :looter_killed_times, 0)} times<br/>
        """
      else
        _other -> "No raid activity"
      end

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, """
    <html>
      <head>
        <meta http-equiv="refresh" content="5">
      <head/>
      <body>
        Status: #{status}<br/>
        <br/>
        Pause Bot:<br/>
        <a href="/pause?duration=15">for 15 minutes</a><br/>
        <a href="/pause?duration=30">for 30 minutes</a><br/>
        <a href="/pause?duration=60">for 1 hour</a><br/>
        <br/>
        <a href="/unpause">UnPause</a>
        <br/>
        <br/>
        <br/>
        Ships on mission: <br/>
        #{ships_on_mission}<br/>
        <br/>
        <a href="/pause_missions">Pause All</a><br/>
        <a href="/unpause_missions">Unpause All</a><br/>
        <br/>
        <br/>
        <a href="/scan_enemies">Scan enemies</a><br/>
        <br/>
        Missions: <br/>
        - <a href="/set_multitasking_mission_plan">Faction + Miners + Defence (default)</a><br/>
        - <a href="/set_mining_mission_plan">Miners + Mining</a><br/>
        - <a href="/set_overcargo_hunting_mission_plan">Hunt G3 miners</a><br/>
        - <a href="/set_agressive_overcargo_hunting_mission_plan">Hunt G2/G3 miners</a><br/>
        - <a href="/set_faction_hunting_mission_plan">Hunt Klingons</a><br/>
        - <a href="/set_elite_faction_hunting_mission_plan">Hunt Klingons Elite</a><br/>
        - <a href="/set_raid_mission_plan">Raid</a><br/>
        <br/><br/>
        Raid: <br/>
        <form action="/set_raid_mission_plan">
          <input type="text" name="target_user_id">
          <input type="submit" value="Loot">
        </form>
        <br/><br/>
        #{raid_mission}
        <br/><br/>
        Scan: <br/>
        <form action="/scan">
          <input type="text" name="system_id">
          <input type="submit" value="Scan">
        </form>
        <br/><br/>
        Blockade: <br/>
        <form action="/set_blockade_mission_plan">
          <input type="text" name="target_user_id">
          <input type="submit" value="Blockade">
        </form>
      </body>
    </html>
    """)
  end

  get "/scan" do
    %{"system_id" => system_id} = conn.query_params

    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    system = system_id |> String.to_integer() |> Trekmap.Me.get_system(session)
    Trekmap.Bots.GalaxyScanner.scan_and_sync_system(system, session)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/pause" do
    %{"duration" => duration_minutes} = conn.query_params
    duration_seconds = String.to_integer(duration_minutes) * 60
    :ok = Trekmap.Bots.pause_bots_for(duration_seconds)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/unpause" do
    :ok = Trekmap.Bots.start_bots()

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/pause_missions" do
    :ok = Trekmap.Bots.FleetCommander.pause_all_missions()

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/unpause_missions" do
    :ok = Trekmap.Bots.FleetCommander.unpause_all_missions()

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/scan_enemies" do
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, system_ids} = Trekmap.Galaxy.System.Station.list_system_ids_with_enemy_stations(session)

    Task.start(fn ->
      Trekmap.Bots.GalaxyScanner.scan_systems_by_ids(system_ids, session)
    end)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_multitasking_mission_plan" do
    mission_plan = Trekmap.Bots.Admiral.MissionPlans.multitasking_mission_plan()
    Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_mining_mission_plan" do
    mission_plan = Trekmap.Bots.Admiral.MissionPlans.mining_mission_plan()
    Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_overcargo_hunting_mission_plan" do
    mission_plan = Trekmap.Bots.Admiral.MissionPlans.overcargo_hunting_mission_plan()
    Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_agressive_overcargo_hunting_mission_plan" do
    mission_plan = Trekmap.Bots.Admiral.MissionPlans.agressive_overcargo_hunting_mission_plan()
    Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_faction_hunting_mission_plan" do
    mission_plan = Trekmap.Bots.Admiral.MissionPlans.faction_hunting_mission_plan()
    Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_elite_faction_hunting_mission_plan" do
    mission_plan = Trekmap.Bots.Admiral.MissionPlans.elite_faction_hunting_mission_plan()
    Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_raid_mission_plan" do
    mission_plan =
      case conn.query_params do
        %{"target_user_id" => target_user_id} ->
          with {:ok, target_station} = Trekmap.Galaxy.System.Station.find_station(target_user_id) do
            Trekmap.Bots.Admiral.MissionPlans.raid_mission_plan(target_station)
          end

        _other ->
          Trekmap.Bots.Admiral.MissionPlans.raid_mission_plan()
      end

    Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_blockade_mission_plan" do
    %{"target_user_id" => target_user_id} = conn.query_params
    {:ok, target_station} = Trekmap.Galaxy.System.Station.find_station(target_user_id)
    mission_plan = Trekmap.Bots.Admiral.MissionPlans.blockade_mission_plan(target_station)
    Trekmap.Bots.Admiral.set_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp format_time(seconds) when seconds <= 0 do
    ""
  end

  defp format_time(seconds) do
    %{hour: hour, minute: minute, second: second} =
      %Time{hour: 0, minute: 0, second: 0}
      |> Time.add(seconds, :second)

    [
      if(hour != 0, do: "#{hour}h"),
      if(minute != 0, do: "#{minute}m"),
      "#{second}s"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
