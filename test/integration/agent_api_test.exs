defmodule DDtrace.AgentAPITest do
  # @fake_agent_url Application.compile_env!(:dd_trace_ex, :agent_url)
  use ExUnit.Case

  setup do
    port = Application.fetch_env!(:dd_trace_ex, :agent_port)
    bypass = Bypass.open(port: port)

    {:ok, bypass: bypass}
  end

  test "send_traces/1 hits PUT /v0.3/traces", %{bypass: bypass} do
    span = TestHelper.single_span()

    Bypass.expect_once(bypass, "PUT", "/v0.3/traces", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, [])
      enc_trace = [span] |> Jason.encode!()
      assert body == enc_trace

      conn
      |> Plug.Conn.resp(200, "OK\n")
    end)

    assert {:ok, %Finch.Response{status: 200, body: "OK\n"}} =
             DDTrace.AgentAPI.send_traces([span])
  end

  test "send_traces/1 fails PUT /v0.3/traces", %{bypass: bypass} do
    traces = TestHelper.traces()

    Bypass.down(bypass)

    assert {:error, %Mint.TransportError{reason: :econnrefused}, ^traces} =
             DDTrace.AgentAPI.send_traces(traces)
  end

  @tag run: true
  test "send_traces/1 partially fails PUT /v0.3/traces", %{bypass: bypass} do
    traces = TestHelper.traces()
    test_pid = self()

    Bypass.expect_once(bypass, "PUT", "/v0.3/traces", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, [])
      enc_traces = Enum.at(traces, 0)
      assert body == Jason.encode!([enc_traces])

      send(test_pid, :first_request_done)

      Plug.Conn.send_resp(conn, 200, "OK\n")
    end)

    task =
      Task.async(fn ->
        DDTrace.AgentAPI.send_traces(traces)
      end)

    assert_receive :first_request_done, 1000

    Bypass.down(bypass)

    supposed_failed_spans = Enum.take(traces, 1)

    assert {:error, %Mint.TransportError{}, ^supposed_failed_spans} = Task.await(task)
  end
end
