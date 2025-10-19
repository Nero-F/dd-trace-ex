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
      |> expect(:send_traces, fn _traces ->
        {:error, "unexpected event occurs", [@span.trace_id]}
      end)
      |> expect(:send_traces, fn _traces ->
        {:error, "unexpected event occurs", [@span.trace_id]}
      end)
      |> expect(:send_traces, fn _traces ->
        {:error, "unexpected event occurs", [@span.trace_id]}
      end)

      send(pid, :flush)
      Process.send_after(pid, {:cb_state, {test_pid, ref}}, 50)
      assert_receive({^ref, circuit_breaker})
      assert circuit_breaker.state == :open
    end
  end

  describe "circuit_breaker Agent reachable after fail" do
    test "circuit breaker recover after fails" do
      test_pid = self()
      ref = make_ref()

      pid = start_supervised!({DDTrace.SpanCollector, [mode: :manual]})
      DDTrace.SpanCollector.add_span(@span)

      for _ <- 1..3 do
        @agent_api_module
        |> expect(:send_traces, fn _traces ->
          {:error, "unexpected event occurs", [@span.trace_id]}
        end)

        send(pid, :flush)
      end

      Process.send_after(pid, {:cb_state, {test_pid, ref}}, 90)
      assert_receive({^ref, circuit_breaker})
      assert circuit_breaker.state == :open

      DDTrace.SpanCollector.add_span(@span)

      @agent_api_module |> expect(:send_traces, fn _traces -> {:ok, :resp} end)
      # Wait for circuit breaker timeout expiration
      t = (System.monotonic_time(:millisecond) - circuit_breaker.next_attempt) |> abs()
      Process.send_after(pid, :flush, t)
      Process.send_after(pid, {:cb_state, {test_pid, ref}}, t)
      assert_receive({^ref, circuit_breaker}, t + 1_000)

      assert circuit_breaker.state == :closed
    end
  end

  describe "Batch partially sent" do
    test "Span collector tries to resend failed spans" do
      test_pid = self()
      ref = make_ref()

      traces = [
        @span,
        %DDTrace.Span{
          duration: 12345,
          name: "elixir APM client",
          resource: "test",
          service: "Integration test",
          span_id: 989_654_321,
          start: 0,
          trace_id: 125_456_789
        },
        %DDTrace.Span{
          duration: 12345,
          name: "elixir APM client",
          resource: "test",
          service: "Integration test",
          span_id: 990_654_321,
          start: 0,
          trace_id: 127_456_789
        }
      ]

      pid = start_supervised!({DDTrace.SpanCollector, [mode: :semi_periodic]})
      Enum.each(traces, &DDTrace.SpanCollector.add_span/1)

      @agent_api_module
      |> expect(:send_traces, fn _traces ->
        {:error, "unexpected event occurs", [125_456_789]}
      end)
      |> expect(:send_traces, fn _traces ->
        {:error, "unexpected event occurs", [127_456_789]}
      end)
      |> expect(:send_traces, fn _traces ->
        {:ok, :resp}
      end)

      send(pid, :flush)
      Process.send_after(pid, {:cb_state, {test_pid, ref}}, 50)
      assert_receive({^ref, circuit_breaker})
      assert circuit_breaker.state == :closed
    end
  end
end
