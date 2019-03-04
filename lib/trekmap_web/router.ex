defmodule Trekmap.Router do
  use Plug.Router

  plug(:fetch_query_params)
  # plug(Plug.Logger)

  plug(BasicAuth, use_config: {:trekmap, :auth})

  plug(:match)
  plug(:dispatch)

  get "/" do
    {status, ships_on_mission} =
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
                fleet_id: fleet_id,
                mission_paused: mission_paused,
                clearence_granted: clearence_granted,
                system: %{name: system_name},
                fleet: %{
                  state: state,
                  hull_health: hull_health,
                  cargo_size: cargo_size,
                  remaining_travel_time: remaining_travel_time,
                  cargo_bay_size: cargo_bay_size
                }
              } ->
                task_name =
                  case strategy do
                    Trekmap.Bots.FleetCommander.Strategies.StationDefender -> "Defending Station"
                    Trekmap.Bots.FleetCommander.Strategies.MinerHunter -> "Hunting Miners"
                    other -> inspect(other)
                  end

                ship_name =
                  cond do
                    fleet_id == Trekmap.Me.Fleet.jellyfish_fleet_id() -> "Jellyfish"
                    fleet_id == Trekmap.Me.Fleet.northstar_fleet_id() -> "North Star"
                    fleet_id == Trekmap.Me.Fleet.kehra_fleet_id() -> "Kehra"
                    true -> to_string(fleet_id)
                  end

                mission_paused = if mission_paused, do: "; PAUSED", else: ""

                clearence_granted =
                  if clearence_granted, do: "", else: "; <b>WAITING FOR CLEARENCE</b>"

                [
                  " - #{ship_name}: #{task_name} #{inspect(state)} #{remaining_travel_time}s " <>
                    "at #{system_name} (H:#{trunc(hull_health || 100)}%; " <>
                    "C:#{trunc(cargo_size || 0)}/#{trunc(cargo_bay_size || 0)}" <>
                    "#{mission_paused}#{clearence_granted})"
                ]
            end)
            |> Enum.join(",</br> ")

          {"Running#{under_attack}#{shield_enabled} / Damaged #{trunc(fleet_damage_ratio)}%",
           ships_on_mission}

        :starting ->
          {"Starting", ""}

        {:scheduled, timeout} ->
          minutes = trunc(timeout / 60)
          seconds = rem(timeout, 60) |> to_string() |> String.pad_leading(2, "0")
          {"Would start in #{minutes}:#{seconds}", ""}
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
        Missions: <br/>
        - <a href="/set_aggresive_mining_hunting_mission">Agressive Mining Hunting</a><br/>
        - <a href="/set_passive_mining_hunting_mission">Passive Mining Hunting</a><br/>
      </body>
    </html>
    """)
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

  get "/set_aggresive_mining_hunting_mission" do
    mission_plan = Trekmap.Bots.Admiral.agressive_mining_hunting_mission_plan()
    Trekmap.Bots.FleetCommander.apply_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/set_passive_mining_hunting_mission" do
    mission_plan = Trekmap.Bots.Admiral.passive_mining_hunting_mission_plan()
    Trekmap.Bots.FleetCommander.apply_mission_plan(mission_plan)

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
