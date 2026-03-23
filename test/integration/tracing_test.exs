defmodule TracingTest do
  use ExUnit.Case

  alias DDTrace.Tracer
  alias DDTrace.Context

  setup do
    start_supervised!({DDTrace.SpanCollector, [mode: :manual]})

    :ok
  end

  describe "Trace Lifecycle" do
    test "Basic Trace" do
      ctx = Tracer.start("test trace")

      assert ctx == Process.get(:dd_trace_ctx)

      assert ctx.root_span == ctx.current_span
      assert ctx.span_stack == []

      Tracer.stop(ctx)
      assert Process.get(:dd_trace_ctx) == nil
    end

    test "sequential Trace" do
      ctx = Tracer.start("test trace 1")

      assert ctx == Process.get(:dd_trace_ctx)

      assert ctx.root_span == ctx.current_span
      assert ctx.span_stack == []

      Tracer.stop(ctx)
      assert Process.get(:dd_trace_ctx) == nil
      ctx = Tracer.start("test trace 2")

      assert ctx == Process.get(:dd_trace_ctx)

      assert ctx.root_span == ctx.current_span
      assert ctx.span_stack == []

      Tracer.stop(ctx)
      assert Process.get(:dd_trace_ctx) == nil
      assert Process.get(:dd_trace_ctx) == nil
    end

    test "Start a trace inside a Tracer does nothing" do
      ctx = Tracer.start("Parent trace")
      assert ctx == Process.get(:dd_trace_ctx)

      assert ctx.root_span == ctx.current_span
      assert ctx.span_stack == []

      ctx2 = Tracer.start("fooo")

      assert ctx == ctx2

      Tracer.stop(ctx)
    end

    test "Start a span inside a span" do
      Tracer.start("trace")

      Tracer.start_span("parent span")
      Tracer.start_span("child span")

      current_ctx = Context.get_current()
      [parent_span | _rest] = current_ctx.span_stack

      assert current_ctx.current_span.parent_id == parent_span.span_id

      Tracer.start_span("grand child span")

      current_ctx = Context.get_current()
      [parent_span | _rest] = current_ctx.span_stack
      assert current_ctx.current_span.parent_id == parent_span.span_id

      Tracer.stop()
    end

    test "Consecutive Spans" do
      Tracer.start("trace")
      Tracer.start_span("spans1")

      current_ctx = Context.get_current()
      assert current_ctx.current_span.parent_id == current_ctx.root_span.span_id

      Tracer.finish_span()

      Tracer.start_span("spans2")

      current_ctx = Context.get_current()
      assert current_ctx.current_span.parent_id == current_ctx.root_span.span_id

      Tracer.finish_span()

      Tracer.stop()
    end

    test "SpanOptions are inherted from root span" do
      root_span = Tracer.start("trace", resource: "RES1", service: "TEST").root_span
      child_span = Tracer.start_span("spans1").current_span

      assert root_span.opts == child_span.opts

      Tracer.finish_span()

      child_span2 = Tracer.start_span("spans2").current_span

      assert root_span.opts.resource == "RES1"
      assert root_span.opts.service == "TEST"
      assert root_span.opts == child_span2.opts

      Tracer.finish_span()

      Tracer.stop()
    end

    @tag run: true
    test "SpanOptions can be inserted in child span" do
      Tracer.start("trace", resource: "RES1", service: "TEST")
      span1 = Tracer.start_span("spans1").current_span
      span2 = Tracer.start_span("spans2", resource: "RES2").current_span

      assert span1.opts.service == span2.opts.service
      assert span1.opts.resource != span2.opts.resource

      Tracer.stop()
    end
  end
end
