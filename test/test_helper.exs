{:ok, _pid} = Finch.start_link(name: DDFinch)
ExUnit.start()

defmodule TestHelper do
  @single_span %DDTrace.Span{
    duration: 12345,
    name: "elixir APM client",
    resource: "test",
    service: "AgentAPITest",
    span_id: 987_654_321,
    start: 0,
    trace_id: 123_456_789
  }

  def single_span(), do: @single_span

  def traces() do
    Enum.map(
      1..3,
      fn n ->
        %{@single_span | trace_id: @single_span.trace_id + n, span_id: @single_span.span_id + n}
      end
    )
  end
end
