defmodule Appman.Manager do
  use GenServer
  require Logger

  @doc """
  GenServer state is a map with keys being app names and values being
  app path, status, connector pid, initialization ref (for initialization timeout)
  and restart marker (for restart).
  """

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: {:global, __MODULE__})
  end

  def init(_args) do
    {:ok, %{}}
  end

  @doc """
  Registration callback. App goes to registered state.
  """
  def handle_call({:register, name, path}, _, state) do
    case Map.has_key?(state, name) do
      true ->
        Logger.warn("#{name} is already registered.")
        {:reply, :error, state}

      false ->
        new_state = Map.put(state, name, %{status: :registered, path: path})
        {:reply, :ok, new_state}
    end
  end

  @doc """
  List apps callback.
  """
  def handle_call(:list, _, state) do
    info =
      Enum.map(state, fn {name, %{path: path, status: status}} ->
        [name: name, path: path, status: status]
      end)

    {:reply, info, state}
  end

  @doc """
  Start callback. Initiates app startup. App goes to initializing state.
  Sends message to handle initialization timeout.
  Started process must be in registered state.
  """
  def handle_cast({:start, name}, state) do
    case Map.get(state, name) do
      %{status: :registered, path: path} = app ->
        Logger.info("Starting #{name}...")
        name_prefix = Node.self() |> to_string() |> String.split("@") |> List.first()

        # Run startup command in a separate process
        start_script = Application.get_env(:appman, :start_node_script)

        task =
          Task.Supervisor.async_nolink(Appman.TaskSupervisor, fn ->
            command = File.cwd!() <> "/#{start_script} #{name_prefix <> "_" <> name} #{path}"
            :os.cmd(to_charlist(command))
          end)

        Process.send_after(self(), {:init_timeout, task.ref}, 3000)

        new_app = app |> Map.put(:status, :initializing) |> Map.put(:init_ref, task.ref)
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      nil ->
        Logger.warn("#{name} is not registered.")
        {:noreply, state}

      _ ->
        Logger.warn("#{name} is not in a runnable state.")
        {:noreply, state}
    end
  end

  @doc """
  Callback for 'ready' message from app's Connector.
  Completes initialization. App goes to running state. Starts monitoring app.
  If the app is not in initializing state, ask Connector to stop.
  """
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
        Logger.info("#{name} is running.")
        Node.monitor(node, true)
        GenServer.cast(pid, {:server_pid, self()})

        new_app =
          app
          |> Map.put(:status, :running)
          |> Map.put(:pid, pid)
          |> Map.put(:init_ref, nil)

        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      _ ->
        GenServer.cast(pid, :stop)
        {:noreply, state}
    end
  end

  @doc """
  Stop callback. Ask app's Connector to stop.
  App does not leave running state yet, waits for nodedown message from monitor.
  Can only stop apps in running state.
  """
  def handle_cast({:stop, name}, state) do
    case Map.get(state, name) do
      %{status: :running, pid: pid} ->
        Logger.info("Stopping #{name}...")
        GenServer.cast(pid, :stop)

      _ ->
        Logger.warn("#{name} is not running.")
    end

    {:noreply, state}
  end

  @doc """
  Restart callback. Similar to stop callback.
  Marks app for restart - it will be started right after nodedown message from monitor.
  """
  def handle_cast({:restart, name}, state) do
    case Map.get(state, name) do
      %{status: :running} = app ->
        Logger.info("Restarting #{name}")
        new_app = Map.put(app, :restart, true)
        new_state = Map.put(state, name, new_app)
        GenServer.cast({:global, __MODULE__}, {:stop, name})
        {:noreply, new_state}

      _ ->
        Logger.warn("#{name} is not running.")
        {:noreply, state}
    end
  end

  @doc """
  Logs callback. Prints app's log file.
  """
  def handle_cast({:logs, name, lines}, state) do
    case Map.get(state, name) do
      nil ->
        Logger.info("${name} not registered.")

      _ ->
        # Run tail command in a separate process.
        Task.Supervisor.async_nolink(Appman.TaskSupervisor, fn ->
          prefix = Node.self() |> to_string() |> String.split("@") |> List.first()
          node_name = prefix <> "_" <> name <> ".log"
          path = "/var/log/appman/"
          logs = System.cmd("tail", ["-n", to_string(lines), path <> node_name])
          Logger.info("Logs for #{name}:\n" <> elem(logs, 0))
        end)
    end

    {:noreply, state}
  end

  @doc """
  Callback for nodedown message.
  Can be caused by natural app completion, stop command or crash.
  """
  def handle_info({:nodedown, node}, state) do
    name =
      node
      |> to_string()
      |> String.split("@")
      |> List.first()
      |> String.split("_")
      |> Enum.at(1)

    case Map.get(state, name) do
      # nodedown caused by restart. Must start again.
      %{status: :running, restart: true} = app ->
        Logger.info("#{name} stopped.")
        GenServer.cast({:global, __MODULE__}, {:start, name})
        new_app = %{app | status: :registered, restart: false}
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      %{status: :running} = app ->
        Logger.info("#{name} stopped.")
        new_app = %{app | status: :registered, pid: nil}
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  @doc """
  Initialization timeout callback. Ends initialization unsuccessfully.
  """
  def handle_info({:init_timeout, ref}, state) when Kernel.is_reference(ref) do
    case Enum.find(state, fn {_, app} -> Map.get(app, :init_ref) == ref end) do
      {name, app} ->
        Logger.warn("#{name} initialization failed.")
        new_app = %{app | status: :registered, init_ref: nil}
        new_state = Map.put(state, name, new_app)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  @doc """
  Ignore messages from task execution.
  """
  def handle_info({:DOWN, ref, _, _, _}, state) when Kernel.is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({ref, _answer}, state) when Kernel.is_reference(ref) do
    {:noreply, state}
  end
end
