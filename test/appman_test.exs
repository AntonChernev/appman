defmodule AppmanTest do
  use ExUnit.Case
  doctest Appman

  test "greets the world" do
    assert Appman.hello() == :world
  end
end
