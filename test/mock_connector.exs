defmodule Appman.Connector do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: {:global, :mock_connector})
  end

  def init(_args) do
    Node.start(:"test_test@127.0.0.1")
    {:ok, nil}
  end

  def handle_call({:ping, manager_node}, _, _) do
    Node.connect(manager_node)
    Process.sleep(1000)
    GenServer.cast({:global, Appman.Manager}, {:node_running, Node.self(), self()})
    {:reply, :ok, manager_node}
  end

  def handle_cast({:server_pid, _}, state) do
    {:noreply, state}
  end

  def handle_cast(:stop, state) do
    Node.disconnect(state)
    {:noreply, nil}
  end
end

Appman.Connector.start_link([])
Process.sleep(:infinity)
