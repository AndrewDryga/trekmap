defmodule Trekmap.Locker do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_bucket) do
    {:ok, %{}}
  end

  def lock(id) do
    GenServer.call(__MODULE__, {:lock, id})
  end

  def locked?(id) do
    GenServer.call(__MODULE__, {:locked?, id})
  end

  def unlock(id) do
    GenServer.cast(__MODULE__, {:unlock, id})
  end

  def unlock_caller_locks do
    GenServer.cast(__MODULE__, {:unlock_all_locks, self()})
  end

  def handle_call({:lock, id}, {pid, _ref}, locks) do
    Process.monitor(pid)
    locks = Map.put(locks, id, pid)
    {:reply, :ok, locks}
  end

  def handle_call({:locked?, id}, {pid, _ref}, locks) do
    locked? =
      if lock_owner_pid = Map.get(locks, id) do
        lock_owner_pid != pid
      else
        false
      end

    {:reply, locked?, locks}
  end

  def handle_cast({:unlock, id}, locks) do
    locks = Map.delete(locks, id)
    {:noreply, locks}
  end

  def handle_cast({:unlock_all_locks, pid}, locks) do
    locks =
      Enum.flat_map(locks, fn {id, lock_owner_pid} ->
        if pid == lock_owner_pid do
          []
        else
          [{id, lock_owner_pid}]
        end
      end)
      |> Enum.into(%{})

    {:noreply, locks}
  end

  def handle_info({:DOWN, _monitor_ref, :process, pid, _reason}, locks) do
    locks =
      Enum.flat_map(locks, fn {id, lock_owner_pid} ->
        if pid == lock_owner_pid do
          []
        else
          {id, lock_owner_pid}
        end
      end)
      |> Enum.into(%{})

    {:noreply, locks}
  end
end
