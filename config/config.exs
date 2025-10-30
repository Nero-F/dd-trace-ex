import Config

# _default_trace_obfuscation_query_string_regexp = ~r/(?i)(?:(?:"|%22)?)(?:(?:old[-_]?|new[-_]?)?p(?:ass)?w(?:or)?d(?:1|2)?|pass(?:[-_]?phrase)?|secret|(?:api[-_]?|private[-_]?|public[-_]?|access[-_]?|secret[-_]?|app(?:lication)?[-_]?)key(?:[-_]?id)?|token|consumer[-_]?(?:id|key|secret)|sign(?:ed|ature)?|auth(?:entication|orization)?)(?:(?:\s|%20)*(?:=|%3D)[^&]+|(?:"|%22)(?:\s|%20)*(?::|%3A)(?:\s|%20)*(?:"|%22)(?:%2[^2]|%[^2]|[^"%])+(?:"|%22))|(?:bearer(?:\s|%20)+[a-z0-9._\-]+|token(?::|%3A)[a-z0-9]{13}|gh[opsu]_[0-9a-zA-Z]{36}|ey[I-L](?:[\w=-]|%3D)+\.ey[I-L](?:[\w=-]|%3D)+(?:\.(?:[\w.+/=-]|%3D|%2F|%2B)+)?|-{5}BEGIN(?:[a-z\s]|%20)+PRIVATE(?:\s|%20)KEY-{5}[^\-]+-{5}END(?:[a-z\s]|%20)+PRIVATE(?:\s|%20)KEY(?:-{5})?(?:\n|%0A)?|(?:ssh-(?:rsa|dss)|ecdsa-[a-z0-9]+-[a-z0-9]+)(?:\s|%20|%09)+(?:[a-z0-9/.+]|%2F|%5C|%2B){100,}(?:=|%3D)*(?:(?:\s|%20|%09)+[a-z0-9._-]+)?)/)

parse_bool = fn value, default ->
  case value do
    "true" -> true
    "false" -> false
    _ -> default
  end
end

config :dd_trace_ex,
  # Agent
  agent_url: System.get_env("DD_TRACE_AGENT_URL", "http://localhost:8126"),
  agent_host: System.get_env("DD_AGENT_HOST", "127.0.0.7"),
  agent_port: System.get_env("DD_TRACE_AGENT_PORT", "8126") |> String.to_integer(),
  agent_api_module: DDTrace.AgentAPI,

  # Unified Service Tagging
  version: System.get_env("DD_VERSION", nil),
  service: System.get_env("DD_SERVICE", nil),
  env: System.get_env("DD_ENV", nil),
  tags: System.get_env("DD_TAGS", nil),

  # Diagnostics
  log_directory: System.get_env("DD_TRACE_LOG_DIRECTORY", nil),

  # Metrics
  runtime_metrics_enable: System.get_env("DD_RUNTIME_METRICS_ENABLE") |> parse_bool.(false),

  # Traces
  # apm_tracing_enabled: System.get_env("DD_APM_TRACING_ENABLED") |> parse_bool.(true),
  trace_enabled?: System.get_env("DD_TRACE_ENABLED") |> parse_bool.(true),
  trace_rate_limit: System.get_env("DD_TRACE_RATE_LIMIT", "100") |> String.to_integer(),
  trace_header_tags: System.get_env("DD_TRACE_HEADER_TAGS", nil),
  trace_sample_rate: System.get_env("DD_TRACE_SAMPLE_RATE", "-1") |> String.to_integer(),
  trace_sampling_rules: System.get_env("DD_TRACE_SAMPLING_RULES", nil),
  # trace_obfuscation_query_string_regexp: System.get_env("DD_TRACE_OBFUSCATION_QUERY_STRING_REGEXP", default_trace_obfuscation_query_string_regexp),
  trace_128_bit_traceid_generation_enabled?:
    System.get_env("DD_TRACE_128_BIT_TRACEID_GENERATION_ENABLED") |> parse_bool.(true),
  trace_128_bit_traceid_logging_enabled?:
    System.get_env("DD_TRACE_128_BIT_TRACEID_LOGGING_ENABLED") |> parse_bool.(true),
  trace_client_ip_enabled?: System.get_env("DD_TRACE_CLIENT_IP_ENABLED") |> parse_bool.(true),
  trace_experimental_features_enabled?:
    System.get_env("DD_TRACE_EXPERIMENTAL_FEATURES_ENABLED", nil),

  # Serverless
  logs_injection: System.get_env("DD_LOGS_INJECTION") |> parse_bool.(true),

  # Integration
  # DD_TRACE_<INTEGRATION>_ENABLED
  trace_http_client_error_statuses:
    System.get_env("DD_TRACE_HTTP_CLIENT_ERROR_STATUSES", "400-499"),
  trace_http_server_error_statuses:
    System.get_env("DD_TRACE_HTTP_SERVER_ERROR_STATUSES", "500-599"),
  trace_http_client_tag_query_string?:
    System.get_env("DD_TRACE_HTTP_CLIENT_TAG_QUERY_STRING") |> parse_bool.(true),
  trace_client_ip_header: System.get_env("DD_TRACE_CLIENT_IP_HEADER", nil),

  # Context Propagation
  trace_baggage_max_items:
    System.get_env("DD_TRACE_BAGGAGE_MAX_ITEMS", "64") |> String.to_integer(),
  trace_baggage_max_bytes:
    System.get_env("DD_TRACE_BAGGAGE_MAX_BYTES", "8192") |> String.to_integer(),
  trace_baggage_tag_keys:
    System.get_env("DD_TRACE_BAGGAGE_TAG_KEYS", "user.id,session.id,account.id")

import_config "#{config_env()}.exs"
