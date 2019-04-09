defmodule Trekmap.Bots.ChestCollector do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, %{session: session}, :timer.minutes(1)}
  end

  def handle_info(:timeout, %{session: session} = state) do
    Trekmap.Me.Chests.open_all_chests(session)
    Process.send_after(self(), :timeout, :timer.minutes(10))
    {:noreply, state}
  end
end
