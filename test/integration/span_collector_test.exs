defmodule Integration.SpanCollectorTest do
  use ExUnit.Case

  @span %DDTrace.Span{
    duration: 12345,
    name: "elixir APM client",
    resource: "test",
    service: "Integration test",
    span_id: 987_654_321,
    start: 0,
    trace_id: 123_456_789
  }

  import Mox

  setup [:set_mox_from_context, :verify_on_exit!]

  test "when the process `flush` and Circuit Breaker is closed, the AgentAPI interface is called" do
    test_pid = self()
    ref = make_ref()

    pid = start_supervised!({DDTrace.SpanCollector, [mode: :manual]})
    DDTrace.SpanCollector.add_span(@span)

    expect(DDTrace.AgentAPIMock, :send_traces, fn _traces ->
      # assert trace
      send(test_pid, {:send_traces_called, ref})
      :ok
    end)

    send(pid, :flush)

    assert_receive({:send_traces_called, ^ref})
  end
end
