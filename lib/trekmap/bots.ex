defmodule Trekmap.Bots do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def pause_bots_for(timeout) do
    Logger.warn("Stopping bots for #{timeout} seconds")
    timeout = :timer.seconds(timeout)

    with :ok <- GenServer.call(__MODULE__, {:start_in, timeout}) do
      Trekmap.Bots.Supervisor.stop_bots()
    end
  end

  def start_bots do
    GenServer.call(__MODULE__, :start, 30_000)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @impl true
  def init([]) do
    {:ok, %{timer_ref: nil}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    if Trekmap.Bots.Supervisor.bots_active?() do
      {:reply, :running, state}
    else
      if timer_ref = state.timer_ref do
        timer = Process.read_timer(timer_ref)
        {:reply, {:scheduled, trunc(timer / 1000)}, state}
      else
        {:reply, :starting, state}
      end
    end
  end

  @impl true
  def handle_call({:start_in, timeout}, _from, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref, async: false)
    end

    timer_ref = Process.send_after(self(), :start, timeout)

    {:reply, :ok, %{timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(:start, _from, state) do
    {:ok, state} = start(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:start, state) do
    {:ok, state} = start(state)
    {:noreply, state}
  end

  defp start(state) do
    Logger.warn("Starting bots")

    if state.timer_ref do
      Process.cancel_timer(state.timer_ref, async: false)
    end

    {:ok, _pid} =
      case Trekmap.Bots.Supervisor.start_bots() do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
      end

    {:ok, %{timer_ref: nil}}
  end
end
