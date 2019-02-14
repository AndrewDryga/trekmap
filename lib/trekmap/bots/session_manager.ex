defmodule Trekmap.Bots.SessionManager do
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

    {home_fleet, _deployed_fleets, _defense_stations} =
      Trekmap.Me.list_ships_and_defences(session)

    fleet_id =
      home_fleet
      |> List.first()
      |> Map.get("fleet_id")
      |> String.to_integer()

    {:ok, %{session: %{session | fleet_id: fleet_id}}}
  end

  def handle_call(:fetch_session, _from, %{session: session} = state) do
    if Trekmap.Session.session_instance_valid?(session) do
      {:reply, {:ok, session}, state}
    else
      Logger.info("Session invalidated")
      {:ok, %{session: session} = state} = init([])
      {:reply, {:ok, session}, state}
    end
  end
end
