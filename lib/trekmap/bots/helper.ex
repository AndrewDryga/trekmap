defmodule Trekmap.Bots.Helper do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, %{session: session}, 0}
  end

  def handle_info(:timeout, %{session: session} = state) do
    Trekmap.Me.Job.help_all(session)
    Process.send_after(self(), :timeout, 5_000)
    {:noreply, state}
  end
end
