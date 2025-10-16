import Config

config :dd_trace_ex,
  agent_api_module: DDTrace.AgentAPIMock,
  agent_port: 4040,
  agent_url: "http://localhost:4040"

config :dd_trace_ex, DDTrace.SpanCollector,
  circuit_breaker_threshold: 3

config :bypass, enable_debug_log: true
