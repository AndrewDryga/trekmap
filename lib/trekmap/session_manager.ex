defmodule Trekmap.SessionManager do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def fetch_session do
    GenServer.call(__MODULE__, :fetch_session)
  end

  def init([]) do
    Logger.info("Starting new auth session")

    session =
      Trekmap.Session.start_session()
      |> Trekmap.Session.start_session_instance()

    {:ok, %{session: session}}
  end

  def handle_call(:fetch_session, _rom, %{session: session} = state) do
    if Trekmap.Session.session_instance_valid?(session) do
      {:reply, {:ok, session}, state}
    else
      Logger.info("Session instance invalidated")
      {:stop, :session_expired, state}
    end
  end
end
