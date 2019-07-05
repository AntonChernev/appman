defmodule AppmanTest do
  use ExUnit.Case

  setup do
    {:ok, _} = Application.ensure_all_started(:appman)

    on_exit(fn ->
      Application.stop(:appman)
    end)

    :ok
  end

  test "registering apps" do
    reply = Appman.register("testapp", "testpath")
    assert reply == :ok
    reply = Appman.register("testapp", "anothertestpath")
    assert reply == :error
  end

  test "listing apps" do
    Appman.register("testapp", "testpath")
    Appman.register("anotherapp", "anotherpath")
    info = Appman.list()
    assert length(info) == 2
    assert Enum.member?(info, name: "testapp", path: "testpath", status: :registered)
    assert Enum.member?(info, name: "anotherapp", path: "anotherpath", status: :registered)
  end

  test "starting apps" do
    Appman.register("testapp", "testpath")
    Appman.start("testapp")

    # Wait for app to go into initializing
    Process.sleep(100)
    info = Appman.list()
    assert Enum.member?(info, name: "testapp", path: "testpath", status: :initializing)

    # Wait for app to timeout
    Process.sleep(3100)
    info = Appman.list()
    assert Enum.member?(info, name: "testapp", path: "testpath", status: :registered)
  end

  test "starting and stopping apps distributed" do
    manager_node = :"test@127.0.0.1"
    connector_node = :"test_test@127.0.0.1"
    Node.start(manager_node)
    Node.connect(connector_node)
    Appman.register("test", "testpath")
    Appman.start("test")
    # Wait for app to go into initializing and for node connection
    Process.sleep(500)

    GenServer.call({:global, :mock_connector}, {:ping, manager_node})
    # Wait for app to go into running
    Process.sleep(100)
    info = Appman.list()
    assert Enum.member?(info, name: "test", path: "testpath", status: :running)

    Appman.restart("test")
    # Wait for app to stop and go into initializing again
    Process.sleep(100)
    Node.connect(connector_node)
    # Wait for node connection
    Process.sleep(500)
    GenServer.call({:global, :mock_connector}, {:ping, manager_node})
    # Wait for app to go into running
    Process.sleep(100)
    assert Enum.member?(info, name: "test", path: "testpath", status: :running)

    Appman.stop("test")
    # Wait for app to stop
    Process.sleep(100)
    info = Appman.list()
    assert Enum.member?(info, name: "test", path: "testpath", status: :registered)
  end
end
