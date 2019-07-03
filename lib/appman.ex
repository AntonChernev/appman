defmodule Appman do
  def register(name, path) when Kernel.is_binary(name) and Kernel.is_binary(path) do
    GenServer.call({:global, Appman.Manager}, {:register, name, path})
  end

  def list() do
    GenServer.call({:global, Appman.Manager}, :list)
  end

  def start(name) when Kernel.is_binary(name) do
    GenServer.cast({:global, Appman.Manager}, {:start, name})
  end

  def stop(name) when Kernel.is_binary(name) do
    GenServer.cast({:global, Appman.Manager}, {:stop, name})
  end

  def restart(name) when Kernel.is_binary(name) do
    GenServer.cast({:global, Appman.Manager}, {:restart, name})
  end
end
