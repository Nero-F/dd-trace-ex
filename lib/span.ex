defmodule DDTrace.Span do
  @moduledoc """
  Span represent a unit of a Trace.

  It is used to track time spend by an applicaton request and its status.
  """

  @typedoc "Used for metadatas"
  @type string_map() :: %{String.t() => String.t()}

  @typedoc "Used for metrics"
  @type metric_map() :: %{String.t() => float()}

  @typedoc """
  Datadog Span model.

  It will be received by the Datadog Agent through a Http API to be handled by Datadog platform

  ## Fields
  * `:name` - Operation name (must not exceed 100 chars)
  * `:trace_id` - Lower 64 bits of the root span identifier
  * `:span_id` - Span identifier
  * `:parent_id` - Span's direct parent identifier
  * `:resource` - Name of the traced resource (must not exceed 100 chars)
  * `:service` - Name of the traced service (must not exceed 100 chars)
  * `:type` - Type of the request (should be one of those: web, db, cache, custom)
  * `:duration` - Duration of the span in nanoseconds
  * `:meta` - A map of metadata
  * `:metrics` - A map of metrics
  * `:start` - Start time of the span in nanoseconds from UNIX Epoch
  * `:error` - Error status of the span; 0 means no error
  """
  @type t() :: %__MODULE__{
          name: String.t(),
          trace_id: integer(),
          span_id: integer(),
          parent_id: integer(),
          resource: String.t(),
          service: String.t(),
          type: String.t(),
          duration: integer(),
          meta: string_map(),
          metrics: metric_map(),
          start: integer(),
          error: integer()
        }

  # TODO: handle msgpack
  @derive Jason.Encoder
  defstruct [
    :name,
    :trace_id,
    :span_id,
    :parent_id,
    :resource,
    :service,
    :type,
    :duration,
    :meta,
    :metrics,
    start: 0,
    error: 0
  ]
end

# defmodule DDTrace.TraceOption do
#   defstruct [:service, :resource, :type]
# end
