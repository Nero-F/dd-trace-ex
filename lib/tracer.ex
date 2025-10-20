defmodule DDTrace.Tracer do
  @moduledoc """
  The Tracer DSL
  """
  alias DDTrace.Context, as: Ctx
  alias DDTrace.MinimalSpan, as: MinSpan
  alias DDTrace.SpanOptions, as: SpanOpts
  alias DDTrace.Span
  alias DDTrace.SpanCollector

  require Logger

  # =================
  # Helper functions
  # =================

  @spec gen_id(boolean) :: integer()
  defp gen_id(force_64 \\ false) do
    if force_64 == false and
         Application.fetch_env!(:dd_trace_ex, :trace_128_bit_traceid_generation_enabled) == true do
      :crypto.strong_rand_bytes(16)
    else
      :crypto.strong_rand_bytes(8)
    end
    |> :binary.decode_unsigned()
  end

  @spec split_128_bits_id(integer) :: {integer(), integer()}
  defp split_128_bits_id(id) do
    <<highest::64, lowest::64>> = <<id::128>>
    {highest, lowest}
  end

  defp check_span_options(%SpanOpts{} = opts), do: opts

  defp check_span_options(opts) when is_list(opts) or is_map(opts) do
    struct!(SpanOpts, opts)
  end

  # ********************
  # End Helper functions
  # ********************

  @doc """
  Start a new trace.

  ## Options
  * `:service` - The service name (defaults to app name).
  * `:resource` - The resource name.
  * `:type` - The span type (:web, :db, :cache, :custom).
  """
  @spec start(String.t(), SpanOpts.t()) :: Ctx.t()
  def start(name, opts \\ %SpanOpts{}) do
    opts = check_span_options(opts)

    case Ctx.get_current() do
      nil ->
        start_new_trace(name, opts)

      ctx ->
        ctx
    end
  end

  @spec start_new_trace(String.t(), SpanOpts.t()) :: Ctx.t()
  defp start_new_trace(name, opts \\ %SpanOpts{}) do
    trace_id = gen_id()
    span_id = gen_id(true)
    start_tt = DateTime.utc_now() |> DateTime.to_unix(:nanosecond)

    root_span = %MinSpan{
      name: name,
      span_id: span_id,
      start: start_tt,
      opts: opts
    }

    ctx = %Ctx{
      trace_id: trace_id,
      current_span: root_span,
      root_span: root_span
    }

    Ctx.set(ctx)

    ctx
  end

  @doc """
  Starts a new Span.

  This is a shorter version of `start_span/3`.
  """
  @spec start_span(String.t(), SpanOpts.t()) :: :ok
  def start_span(name, opts \\ %SpanOpts{}) do
    opts = check_span_options(opts)

    case Ctx.get_current() do
      nil ->
        Logger.error(
          "No trace started yet, can't start a new span.\nYou should try using `DDTrace.Tracer.start/2` first."
        )

      ctx ->
        start_span(ctx, name, opts)
    end

    :ok
  end

  @spec start_span(Ctx.t(), String.t(), SpanOpts.t()) :: Ctx.t()

  @doc """
  Starts a new span with the given `DDTrace.Context`

  ## Options
  Same as `DDTrace.Tracer.start/2` or check the `t:DDTrace.SpanOptions.t/0`

  """
  def start_span(ctx, name, opts) do
    opts = check_span_options(opts)
    span_id = gen_id(true)
    start_tt = DateTime.utc_now() |> DateTime.to_unix(:nanosecond)

    parent_id =
      cond do
        ctx.root_span.span_id == ctx.current_span.span_id && ctx.span_stack == [] ->
          ctx.root_span.span_id

        ctx.root_span.span_id != ctx.current_span.span_id ->
          ctx.current_span.span_id
      end

    new_span = %MinSpan{
      name: name,
      span_id: span_id,
      parent_id: parent_id,
      start: start_tt,
      opts: opts
    }

    parent = ctx.current_span

    new_ctx = %Ctx{ctx | current_span: new_span, span_stack: [parent | ctx.span_stack]}

    Ctx.set(new_ctx)
    Logger.debug("Started span #{name} with id #{span_id}")
    ctx
  end

  @doc """
  Terminate a span.

  A shorter version of `DDTrace.Tracer.finish_span/1`.
  """
  @spec finish_span() :: :ok
  def finish_span() do
    case Ctx.get_current() do
      nil ->
        Logger.error(
          "No span started yet, can't finish any span.\nYou should try using `DDTrace.Tracer.start_span/2` first."
        )

      ctx ->
        finish_span(ctx)
    end
  end

  @doc """
  Terminate a span using the given `DDTrace.Context`.
  """
  @spec finish_span(Ctx.t()) :: :ok
  def finish_span(ctx) do
    case ctx.span_stack do
      [direct_ancestor | rest] ->
        trace_id = split_128_bits_id(ctx.trace_id)

        current_min_span = ctx.current_span
        duration = (current_min_span.start - System.system_time(:nanosecond)) |> abs()

        span = Span.build_from_minimal(current_min_span, trace_id, duration)

        :ok = SpanCollector.add_span(span)
        new_ctx = %{ctx | current_span: direct_ancestor || ctx.root_span, span_stack: rest}
        Ctx.set(new_ctx)

      [] ->
        stop()
    end

    :ok
  end

  @doc """
  Stop the current trace.

  A shorter version of `DDTrace.Tracer.stop/1`.
  """
  @spec stop() :: :ok
  def stop() do
    case Ctx.get_current() do
      nil ->
        Logger.error("No active trace")

      ctx ->
        stop(ctx)
    end

    :ok
  end

  @doc """
  Stop the current trace with the given `DDTrace.Context`.

  If the trace contains unfinished spans, it ends them using tracing context information.
  """
  @spec stop(Ctx.t()) :: :ok
  def stop(ctx) do
    # Checking for unfinished spans
    trace_id = split_128_bits_id(ctx.trace_id)
    duration = (ctx.root_span.start - System.system_time(:nanosecond)) |> abs()

    ctx.span_stack
    |> Enum.reverse()
    |> Enum.each(fn min_span ->
      min_span.opts

      updated_meta =
        min_span.opts.meta ||
          %{}
          |> Map.put("auto_closed", "true")

      min_span = %{min_span | opts: Map.put(min_span.opts, :meta, updated_meta)}

      DDTrace.Span.build_from_minimal(
        min_span,
        trace_id,
        duration
      )
      |> SpanCollector.add_span()
    end)

    DDTrace.Span.build_from_minimal(ctx.current_span, trace_id, duration)
    |> SpanCollector.add_span()

    Ctx.delete()
    :ok
  end
end
