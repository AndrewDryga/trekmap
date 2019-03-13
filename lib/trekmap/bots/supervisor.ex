defmodule Trekmap.Bots.Supervisor do
  use DynamicSupervisor

  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 100_000, max_seconds: 1)
  end

  def start_bots do
    DynamicSupervisor.start_child(__MODULE__, Trekmap.Bots.SupervisorChild)
  end

  def stop_bots do
    case DynamicSupervisor.which_children(__MODULE__) do
      [] ->
        :ok

      [{_, pid, :supervisor, [Trekmap.Bots.SupervisorChild]}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  def bots_active? do
    DynamicSupervisor.count_children(__MODULE__).active > 0
  end
end
