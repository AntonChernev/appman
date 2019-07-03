defmodule Appman.Manager do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: {:global, __MODULE__})
  end

  def init(_args) do
    {:ok, %{}}
  end

  def handle_call({:register, name, path}, _, state) do
    case Map.has_key?(state, name) do
      true ->
        IO.puts("#{name} is already registered.")
        {:reply, :error, state}

      false ->
        new_state = Map.put(state, name, %{status: :registered, path: path})
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:list, _, state) do
    Enum.each(state, fn {name, %{path: path, status: status}} ->
      IO.puts("Name: #{name}, path: #{path}, status: #{status}")
    end)

    {:reply, :ok, state}
  end

  def handle_cast({:start, name}, state) do
    case Map.get(state, name) do
      %{status: :registered, path: path} = app ->
        IO.puts("Starting #{name}...")
        name_prefix = Node.self() |> to_string() |> String.split("@") |> List.first()

        task =
          Task.Supervisor.async_nolink(Appman.TaskSupervisor, fn ->
            command = File.cwd!() <> "/start_node.sh #{name_prefix <> "_" <> name} #{path}"
            :os.cmd(to_charlist(command))
          end)

        Process.send_after(self(), {:init_timeout, task.ref}, 3000)

        new_app = app |> Map.put(:status, :initializing) |> Map.put(:init_ref, task.ref)
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      nil ->
        IO.puts("#{name} is not registered.")
        {:noreply, state}

      _ ->
        IO.puts("#{name} is not in a runnable state.")
        {:noreply, state}
    end
  end

  def handle_cast({:node_running, node, pid}, state) do
    name =
      node
      |> to_string()
      |> String.split("@")
      |> List.first()
      |> String.split("_")
      |> Enum.at(1)

    case Map.get(state, name) do
      %{status: :initializing} = app ->
        IO.puts("#{name} is running.")
        Node.monitor(node, true)
        GenServer.cast(pid, {:server_pid, self()})
        new_app = app |> Map.put(:status, :running) |> Map.put(:pid, pid)
          |> Map.put(:init_ref, nil)
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      _ ->
        GenServer.cast(pid, :stop)
        {:noreply, state}
    end
  end

  def handle_cast({:stop, name}, state) do
    case Map.get(state, name) do
      %{status: :running, pid: pid} ->
        IO.puts("Stopping #{name}...")
        GenServer.cast(pid, :stop)

      _ ->
        IO.puts("#{name} is not running.")
    end

    {:noreply, state}
  end

  def handle_cast({:restart, name}, state) do
    IO.puts("hej pls stop")

    case Map.get(state, name) do
      %{status: :running} = app ->
        IO.puts("Restarting #{name}")
        new_app = Map.put(app, :restart, true)
        new_state = Map.put(state, name, new_app)
        GenServer.cast({:global, __MODULE__}, {:stop, name})
        {:noreply, new_state}

      _ ->
        IO.puts("#{name} is not running.")
        {:noreply, state}
    end
  end

  def handle_info({:nodedown, node}, state) do
    name =
      node
      |> to_string()
      |> String.split("@")
      |> List.first()
      |> String.split("_")
      |> Enum.at(1)

    case Map.get(state, name) do
      %{status: :running, restart: true} = app ->
        IO.puts("#{name} stopped.")
        GenServer.cast({:global, __MODULE__}, {:start, name})
        new_app = %{app | status: :registered, restart: false}
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      %{status: :running} = app ->
        IO.puts("#{name} stopped.")
        new_app = %{app | status: :registered, pid: nil}
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:init_timeout, ref}, state) when Kernel.is_reference(ref) do
    case Enum.find(state, fn {_, app} -> Map.get(app, :init_ref) == ref end) do
      {name, app} ->
        IO.puts("#{name} initializing failed.")
        new_app = %{app | status: :registered, init_ref: nil}
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, _, _, _}, state) when Kernel.is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({ref, _answer}, state) when Kernel.is_reference(ref) do
    {:noreply, state}
  end
end
