defmodule Trekmap.Router do
  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, """
    <html>
    <body>
    Status: Runninng<br/>
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
    IO.inspect(conn)

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("location", "/")
    |> send_resp(200, "paused")
  end

  get "/unpause" do
    IO.inspect(conn)

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("location", "/")
    |> send_resp(200, "unpaused")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
