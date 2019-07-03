defmodule Appman.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Appman.TaskSupervisor},
      {Appman.Manager, []}
    ]

    opts = [strategy: :one_for_one, name: Appman.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
