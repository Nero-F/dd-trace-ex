defmodule DDTrace.AgentAPI.Behaviour do
  alias DDTrace.Span

  @type trace_id() :: number()

  @callback send_traces(span :: [Span.t()]) ::
              {:ok, Finch.Response.t()} | {:error, Exception.t(), [trace_id()]}
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
    traces = Enum.group_by(spans, & &1.trace_id)

    Enum.reduce_while(traces, {:ok, nil, []}, fn {trace_id, spans}, {:ok, _resp, acc} ->
      res =
        Finch.build(
          :put,
          "#{agent_url}/v0.3/traces",
          @headers,
          spans |> Jason.encode!()
        )
        |> Finch.request(DDFinch)

      case res do
        {:ok, resp} -> {:cont, {:ok, resp, [trace_id | acc]}}
        {:error, error} -> {:halt, {:error, error, acc}}
      end
    end)
    |> case do
      {:ok, resp, _traces_sent} ->
        {:ok, resp}

      {:error, resp, traces_sent} ->
        failed_spans =
          Enum.filter(spans, fn span ->
            Enum.any?(traces_sent, &(span.trace_id == &1))
          end)

        failed_spans =
          case failed_spans do
            [] -> spans
            _ -> failed_spans
          end

        {:error, resp, failed_spans}
    end
  end
end
