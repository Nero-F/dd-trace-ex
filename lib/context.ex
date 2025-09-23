defmodule DDTrace.Context do
  @moduledoc """
  Datadog Trace context

  The context stores information about the process's active spans associated with a particular trace_id.
  Its main goal is to keep track of minimal span data throughout the trace lifecycle and manage the 
  hierarchical relationship between spans (parent-child). The context is isolated per process using 
  the Process Dictionary and includes the current span, root span, and a stack for managing nested spans.

  For the complete trace lifecycle, see `DDTrace.Tracer`.
  """

  @typedoc """
  Context structure

  ## Fields
  * `:trace_id` - Current trace id.
  * `:root_span` - Current root minimal span.
  * `:current_span` - Current minimal span.
  * `:span_stack` - List of minimal span direct ancestors.
  """
  @type t() :: %__MODULE__{
          trace_id: integer(),
          root_span: DDTrace.MinimalSpan.t(),
          current_span: DDTrace.MinimalSpan.t(),
          span_stack: list(DDTrace.MinimalSpan.t())
        }

  defstruct [
    :trace_id,
    :current_span,
    :root_span,
    span_stack: []
  ]

  @process_key :dd_trace_ctx

  @doc """
  Return the current Datadog trace context.
  """
  @spec get_current() :: t()
  def get_current(), do: Process.get(@process_key)

  @doc """
  Sets the current Datadog trace context.
  """
  @spec set(t()) :: :ok
  def set(ctx) do
    Process.put(@process_key, ctx)
    :ok
  end

  @doc """
  Clear out the current Datadog trace context.
  """
  @spec delete() :: :ok
  def delete() do
    Process.delete(@process_key)
    :ok
  end
end
