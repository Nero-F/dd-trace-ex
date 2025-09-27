defmodule DDTrace do
  use Application

  @moduledoc """
  DDTrace is a Datadog APM library

  You can use the library to trace and monitor your application using Datadog
  """

  @impl true
  def start(_type, _args) do
    DDTrace.Supervisor.start_link()
  end
end

defmodule DDTrace.Supervisor do
  use Supervisor

  def start_link(init_args \\ nil) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Finch, name: DDFinch},
      DDTrace.SpanCollector
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
