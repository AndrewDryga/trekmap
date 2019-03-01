defmodule Trekmap.Router do
  use Plug.Router

  plug(:fetch_query_params)
  # plug(Plug.Logger)

  plug(BasicAuth, use_config: {:trekmap, :auth})

  plug(:match)
  plug(:dispatch)

  get "/" do
    {status, under_attack?, ships_on_mission} =
      case Trekmap.Bots.get_status() do
        :running ->
          {:ok,
           %{
             under_attack?: under_attack?,
             ships_on_mission: ships_on_mission,
             shield_enabled?: shield_enabled?
           }} = Trekmap.Bots.Guardian.get_report()

          under_attack = if under_attack?, do: ", under_attack", else: ""
          shield_enabled = if shield_enabled?, do: ", shield enabled", else: ""

          {"Running#{under_attack}#{shield_enabled}", under_attack?, ships_on_mission}

        :starting ->
          {"Starting", false, []}

        {:scheduled, timeout} ->
          minutes = trunc(timeout / 60)
          seconds = rem(timeout, 60) |> to_string() |> String.pad_leading(2, "0")
          {"Would start in #{minutes}:#{seconds}", false, []}
      end

    ships_on_mission =
      ships_on_mission
      |> Enum.map(fn fleet_id ->
        cond do
          fleet_id == Trekmap.Me.Fleet.jellyfish_fleet_id() -> "Jellyfish - hunting miners"
          fleet_id == Trekmap.Me.Fleet.northstar_fleet_id() -> "North Star - hunting Klingons"
          fleet_id == Trekmap.Me.Fleet.kehra_fleet_id() -> "Kehra - hunting miners"
          true -> to_string(fleet_id)
        end
      end)
      |> Enum.join(", ")

    ships_on_mission = if ships_on_mission == "", do: "none", else: ships_on_mission

    guardian_buttons =
      if under_attack? do
        ~s|<a href="/disable_defence">Turn under attack mode off and start missions</a><br/>|
      else
        ~s|<a href="/activate_defence">Switch to under attack mode</a><br/>|
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
        Ships on mission: #{ships_on_mission} <br/>
        <br/>
        Pause Bot:<br/>
        <a href="/pause?duration=15">for 15 minutes</a><br/>
        <a href="/pause?duration=30">for 30 minutes</a><br/>
        <a href="/pause?duration=60">for 1 hour</a><br/>
        <br/>
        <a href="/unpause">UnPause</a>
        <br/>
        <br/>
        #{guardian_buttons}
        <br/>
        <a href="/do_daily">Send North Star on daily mission</a><br/>
        <a href="/stop_daily">Return North Star from daily mission</a><br/>
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

  get "/activate_defence" do
    :ok = Trekmap.Bots.Guardian.activate_defence()

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/disable_defence" do
    :ok = Trekmap.Bots.Guardian.disable_defence()

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/do_daily" do
    :ok = Trekmap.Bots.Guardian.do_daily()

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/stop_daily" do
    :ok = Trekmap.Bots.Guardian.stop_daily()

    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
