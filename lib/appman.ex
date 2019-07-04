defmodule Appman do
  @doc """
  Register app so that it can be started.
  Apps have a name and a path to project.
  """
  def register(name, path) when Kernel.is_binary(name) and Kernel.is_binary(path) do
    GenServer.call({:global, Appman.Manager}, {:register, name, path})
  end

  @doc """
  List all apps with their path and status.
  """
  def list() do
    GenServer.call({:global, Appman.Manager}, :list)
  end

  @doc """
  Initiate app startup. App must be registered and not running.
  """
  def start(name) when Kernel.is_binary(name) do
    GenServer.cast({:global, Appman.Manager}, {:start, name})
  end

  @doc """
  Initiate app stop. App must be running.
  """
  def stop(name) when Kernel.is_binary(name) do
    GenServer.cast({:global, Appman.Manager}, {:stop, name})
  end

  @doc """
  Initiate app restart. App must be running.
  """
  def restart(name) when Kernel.is_binary(name) do
    GenServer.cast({:global, Appman.Manager}, {:restart, name})
  end

  @doc """
  Print last <lines> lines of an app's logs. App must be registered.
  """
  def logs(name, lines) when Kernel.is_binary(name) and Kernel.is_number(lines) do
    GenServer.cast({:global, Appman.Manager}, {:logs, name, lines})
  end
end
