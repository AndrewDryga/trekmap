defmodule Trekmap.Bots.NameChanger do
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
    Trekmap.Me.Name.generate_name() |> Trekmap.Me.Name.change_name(session)

    Process.send_after(self(), :timeout, :timer.minutes(15))
    {:noreply, state}
  end
end
