defmodule Trekmap.Router do
  use Plug.Router

  plug(:fetch_query_params)
  # plug(Plug.Logger)

  plug(BasicAuth, use_config: {:trekmap, :auth})

  plug(:match)
  plug(:dispatch)

  get "/" do
    status =
      case Trekmap.Bots.get_status() do
        :running ->
          "Running"

        :starting ->
          "Starting"

        {:scheduled, timeout} ->
          minutes = trunc(timeout / 60)
          seconds = rem(timeout, 60) |> to_string() |> String.pad_leading(2, "0")
          "Would start in #{minutes}:#{seconds}"
      end

    ships_on_mission =
      Trekmap.Bots.FleetCommander.get_ships_on_mission() ++
        Trekmap.Bots.FractionHunter.get_ships_on_mission()

    ships_on_mission =
      Enum.map(fn fleet_id ->
        cond do
          fleet_id == Trekmap.Me.Fleet.jellyfish_fleet_id() -> "Jellyfish - hunting miners"
          fleet_id == Trekmap.Me.Fleet.northstar_fleet_id() -> "Noth Star - hunting Klingons"
          true -> to_string(fleet_id)
        end
      end)
      |> Enum.join(", ")

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

  match _ do
    send_resp(conn, 404, "not found")
  end
end
