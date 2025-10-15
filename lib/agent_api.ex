defmodule DDTrace.AgentAPI.Behaviour do
  alias DDTrace.Span
  @callback send_traces(span :: [Span.t()]) :: {:ok, Finch.Response.t()} | {:error, Exception.t()}
end

defmodule DDTrace.AgentAPI do
  @behaviour DDTrace.AgentAPI.Behaviour

  @default_agent_url Application.compile_env(:dd_trace_ex, :agent_url)

  @headers [
    {"Content-Type", "application/json"},
    {"Datadog-Meta-Lang", "elixir"},
    {"Datadog-Meta-Tracer-Version", "0.1.0"}
  ]

  @impl true
  def send_traces(spans, agent_url \\ @default_agent_url) do
    body = [spans] |> Jason.encode!()

    Finch.build(
      :put,
      "#{agent_url}/v0.3/traces",
      @headers,
      body
    )
    |> Finch.request(DDFinch)
  end
end
