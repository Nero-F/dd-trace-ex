import Config

config :dd_trace_ex,
  agent_api_module: DDTrace.AgentAPIMock,
  agent_port: 4040,
  agent_url: "http://localhost:4040"

config :bypass, enable_debug_log: true
