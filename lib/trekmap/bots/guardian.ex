defmodule Trekmap.Bots.Guardian do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Logger.info("[Guardian] I'm on watch")
    {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
    {:ok, %{session: session}, 0}
  end

  def handle_info(:timeout, %{session: session} = state) do
    with :ok <- Trekmap.Me.full_repair(session) do
      Process.send_after(self(), :timeout, 5_000)
      {:noreply, state}
    else
      {:error, :timeout} ->
        {:ok, session} = Trekmap.Bots.SessionManager.fetch_session()
        Process.send_after(self(), :timeout, 100)
        {:noreply, %{session: session}}
    end
  end
end
