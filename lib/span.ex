defmodule DDTrace.CommonTypes do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      @typedoc "Used for metadatas."
      @type string_map() :: %{String.t() => String.t()}

      @typedoc "Used for metrics."
      @type metric_map() :: %{String.t() => float()}
    end
  end
end

defmodule DDTrace.Span do
  @moduledoc """
  Datadog Span

  A Span represent a unit of a Trace. It is used to track time spend by an applicaton operation and its status.
  """
  use DDTrace.CommonTypes

  @typedoc """
  Datadog Span model

  It will be received by the Datadog Agent through a Http API to be handled by Datadog platform

  ## Fields
  * `:name` - Operation name (must not exceed 100 chars).
  * `:trace_id` - Lower 64 bits of the root span identifier.
  * `:span_id` - Span identifier.
  * `:parent_id` - Span's direct parent identifier.
  * `:resource` - Name of the traced resource (must not exceed 100 chars).
  * `:service` - Name of the traced service (must not exceed 100 chars).
  * `:type` - Type of the request (should be one of those: web, db, cache, custom).
  * `:duration` - Duration of the span in nanoseconds.
  * `:meta` - A map of metadata.
  * `:metrics` - A map of metrics.
  * `:start` - Start time of the span in nanoseconds from UNIX Epoch.
  * `:error` - Error status of the span; 0 means no error.
  """
  @type t() :: %__MODULE__{
          name: String.t(),
          trace_id: integer(),
          span_id: integer(),
          parent_id: integer() | nil,
          resource: String.t(),
          service: String.t(),
          type: String.t(),
          duration: integer(),
          meta: string_map(),
          metrics: metric_map(),
          start: integer(),
          error: integer()
        }

  defstruct [
    :name,
    :trace_id,
    :span_id,
    :duration,
    :resource,
    :service,
    :type,
    :meta,
    :metrics,
    parent_id: nil,
    start: 0,
    error: 0
  ]

  @spec build_from_minimal(
          DDTrace.MinimalSpan.t(),
          {integer(), integer()},
          integer()
        ) ::
          %__MODULE__{}
  def build_from_minimal(min_span, {high, low} = _trace_id, duration) do
    %__MODULE__{
      name: min_span.name,
      trace_id: low,
      span_id: min_span.span_id,
      parent_id: min_span.parent_id,
      resource: min_span.opts[:resource],
      service: min_span.opts[:service],
      type: min_span.opts[:type] || "custom",
      meta: base_metadata(min_span.opts[:meta], high),
      start: min_span.start,
      duration: duration
    }
  end

  @spec base_metadata(string_map(), integer()) :: string_map()
  defp base_metadata(meta, high) do
    if high != 0 do
      meta |> Map.put("_dd.p.tid", high |> Integer.to_string(16) |> String.downcase())
    else
      meta
    end
  end
end

defmodule DDTrace.MinimalSpan do
  @moduledoc """
  Datadog minimum Span

  Represent the first draft of a `DDTrace.Span`, serves as a foundation before its completion.
  """

  alias DDTrace.SpanOptions, as: SpanOpts

  @typedoc """
  ## Fields
  See `t:DDTrace.Span.t/0`
  """
  @type t() :: %__MODULE__{
          name: String.t(),
          span_id: integer(),
          parent_id: integer() | nil,
          start: integer(),
          opts: SpanOpts.t()
        }

  defstruct [:name, :span_id, :start, :opts, parent_id: nil]
end

defmodule DDTrace.SpanOptions do
  @moduledoc """
  Options given to a `DDTrace.Span` and `DDTrace.MinimalSpan`

  The Structure Represent the Options that can be given to a specific span.
  If a field is not present it is inherited from the global trace configuration.
  """
  use DDTrace.CommonTypes

  @typedoc """
  ## Fields
  See `t:DDTrace.Span.t/0`
  """
  @type t() :: %__MODULE__{
          resource: String.t(),
          service: String.t(),
          type: String.t(),
          meta: string_map(),
          metrics: metric_map()
        }
  defstruct [
    :resource,
    :service,
    :type,
    :meta,
    :metrics
  ]
end
