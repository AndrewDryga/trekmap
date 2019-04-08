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

    {:ok, session} = Trekmap.Session.start_session()
    {:ok, session} = start_session_instance(session)

    {:ok, galaxy} = Trekmap.Galaxy.build_systems_graph(session)

    {:ok, {starbase, fleets, deployed_fleets, _ships, _battle_results}} =
      Trekmap.Me.fetch_current_state(session)

    fleet_id =
      (Map.keys(fleets) ++ Map.keys(deployed_fleets))
      |> List.first()
      |> to_integer()

    home_system_id = starbase["location"]["system"]

    {:ok,
     %{
       session: %{
         session
         | fleet_id: fleet_id,
           home_system_id: home_system_id,
           galaxy: galaxy,
           game_config: load_game_config()
       }
     }}
  end

  defp to_integer(binary) when is_binary(binary), do: String.to_integer(binary)
  defp to_integer(numeric), do: numeric

  def start_session_instance(%Trekmap.Session{} = session) do
    with {:ok, session} <- Trekmap.Session.start_session_instance(session) do
      {:ok, session}
    else
      {:error, :retry_later} ->
        Logger.info("Game server is under maintenance")
        :timer.sleep(5_000)
        start_session_instance(session)
    end
  end

  def load_game_config do
    {:ok, %{"hull_specs" => hull_specs}} =
      Trekmap.APIClient.json_request(
        :get,
        "https://live-193-web.startrek.digitgaming.com/static_sync",
        [],
        ""
      )

    hull_specs =
      for spec <- hull_specs, into: %{} do
        {Map.fetch!(spec, "id"), spec}
      end

    %{hull_specs: hull_specs}
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
