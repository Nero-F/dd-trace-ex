defmodule DDtrace.AgentAPITest do
  # @fake_agent_url Application.compile_env!(:dd_trace_ex, :agent_url)
  use ExUnit.Case

  setup do
    port = Application.fetch_env!(:dd_trace_ex, :agent_port)
    bypass = Bypass.open(port: port)

    {:ok, bypass: bypass}
  end

  test "send_traces/1 hits PUT /v0.3/traces", %{bypass: bypass} do
    trace = [
      [
        %DDTrace.Span{
          duration: 12345,
          name: "elixir APM client",
          resource: "test",
          service: "AgentAPITest",
          span_id: 987_654_321,
          start: 0,
          trace_id: 123_456_789
        }
      ]
    ]

    Bypass.expect_once(bypass, "PUT", "/v0.3/traces", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, [])

      enc_trace = [trace] |> Jason.encode!()

      assert body == enc_trace

      conn
      |> Plug.Conn.resp(200, "OK\n")
    end)

    assert {:ok, %Finch.Response{status: 200, body: "OK\n"}} = DDTrace.AgentAPI.send_traces(trace)
  end
end
