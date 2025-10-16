defmodule Integration.SpanCollectorTest do
  use ExUnit.Case

  @agent_api_module Application.compile_env!(:dd_trace_ex, :agent_api_module)

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

    expect(@agent_api_module, :send_traces, fn _traces ->
      send(test_pid, {:send_traces_called, ref})
      :ok
    end)

    send(pid, :flush)

    assert_receive({:send_traces_called, ^ref})
  end

  describe "circuit_breaker Agent unreachable" do
    test "when the process `flush` retries send_traces until circuit_breaker_threshold" do
      test_pid = self()
      ref = make_ref()

      pid = start_supervised!({DDTrace.SpanCollector, [mode: :semi_periodic]})
      DDTrace.SpanCollector.add_span(@span)

      @agent_api_module 
      |> expect( :send_traces, fn _traces -> {:error, "unexpected event occurs"} end)
      |> expect( :send_traces, fn _traces -> {:error, "unexpected event occurs"} end)
      |> expect( :send_traces, fn _traces -> {:error, "unexpected event occurs"} end)

      send(pid, :flush)
      Process.send_after(pid, {:cb_state, {test_pid, ref}}, 50)
      assert_receive({^ref, circuit_breaker})
      assert circuit_breaker.state == :open

    end
  end

  describe "circuit_breaker Agent reachable after fail" do
    @tag run: true
    test "circuit breaker recover after fails" do
      test_pid = self()
      ref = make_ref()

      pid = start_supervised!({DDTrace.SpanCollector, [mode: :manual]})
      DDTrace.SpanCollector.add_span(@span)

      for _ <- 1..3 do
        @agent_api_module 
        |> expect( :send_traces, fn _traces -> {:error, "unexpected event occurs"} end)
        send(pid, :flush)
      end

      Process.send_after(pid, {:cb_state, {test_pid, ref}}, 90)
      assert_receive({^ref, circuit_breaker})
      assert circuit_breaker.state == :open

      DDTrace.SpanCollector.add_span(@span)

      @agent_api_module |> expect(:send_traces, fn _traces -> {:ok, :resp} end)
      # Wait for circuit breaker timeout expiration
      tt = System.monotonic_time(:millisecond) - circuit_breaker.next_attempt |> abs()
      Process.send_after(pid, :flush, tt)
      Process.send_after(pid, {:cb_state, {test_pid, ref}}, tt)
      assert_receive({^ref, circuit_breaker}, tt + 1_000)

      assert circuit_breaker.state == :closed
    end
  end
end
