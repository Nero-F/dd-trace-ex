defmodule DDTrace.Agent.Behaviour do
  alias DDTrace.Span
  @callback send_traces(span :: [Span.t()]) :: {:ok, Finch.Response.t()} | {:error, Exception.t()}
end

defmodule DDTrace.Agent do
  @behaviour DDTrace.Agent.Behaviour

  @headers [
    {"Content-Type", "application/json"},
    {"Datadog-Meta-Lang", "elixir"},
    {"Datadog-Meta-Tracer-Version", "0.1.0"}
  ]

  @impl true
  def send_traces(spans) do
    body = [spans] |> Jason.encode!()
    agent_url = Application.get_env(:dd_trace_ex, :agent_url)

    Finch.build(
      :put,
      "#{agent_url}/v0.3/traces",
      @headers,
      body
    )
    |> Finch.request(DDFinch)
    |> IO.inspect(label: "res")
  end
end
