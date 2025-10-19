defmodule DDTrace.SpanCollector do
  use GenServer

  require Logger

  alias DDTrace.Span

  @agent_api_module Application.compile_env!(:dd_trace_ex, :agent_api_module)

  @default_config [
    flush_interval: 5,
    max_buffer_size: 1_000,
    circuit_breaker_threshold: 2,
    circuit_breaker_max_retry_delay: 30_000,
    backoff_base: 1_000
  ]

  defstruct [
    :mode,
    :config,
    :spans_table,
    circuit_breaker: %{state: :closed, failure_count: 0, last_failure: nil, next_attempt: nil}
  ]

  defp load_config() do
    conf =
      :dd_trace_ex
      |> Application.get_env(__MODULE__, [])

    Keyword.merge(@default_config, conf)
    |> Enum.into(%{})
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec add_span(Span.t()) :: term()
  def add_span(span) do
    GenServer.cast(__MODULE__, {:add_span, span})
  end

  @impl true
  def init(opts) do
    config = load_config()
    mode = Keyword.get(opts, :mode, :periodic)

    table =
      :ets.new(:spans_buffer, [
        :ordered_set,
        :protected,
        :bag,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    cond do
      mode == :periodic -> schedule_flush(config.flush_interval)
      mode == :manual || mode == :semi_periodic -> :ok
    end

    {:ok,
     %__MODULE__{
       mode: mode,
       config: config,
       spans_table: table
     }}
  end

  defp schedule_flush(interval), do: Process.send_after(self(), :flush, interval)

  @impl true
  def handle_cast({:add_span, span}, state) do
    key = {System.system_time(:nanosecond), make_ref()}
    :ets.insert(state.spans_table, {key, span})

    state = maybe_flush_if_full(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    {_res, new_state} = flush_spans(state)

    if state.mode == :semi_periodic || state.mode == :periodic do
      schedule_flush(new_state.config.flush_interval)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:cb_state, from}, state) do
    GenServer.reply(from, state.circuit_breaker)
    {:noreply, state}
  end

  defp maybe_flush_if_full(state) do
    buff_size = :ets.info(state.spans_table, :size)

    if buff_size >= state.config.max_buffer_size do
      {_res, new_state} = flush_spans(state)
      new_state
    else
      state
    end
  end

  defp flush_spans(state) do
    update_state =
      maybe_transition_to_half_open(state)

    case get_circuit_breaker_state(update_state) do
      :open ->
        Logger.debug("Circuit Breaker open, skipping spans flushing")
        {:skipped, update_state}

      :half_open ->
        Logger.debug("Circuit Breaker half_open, trying recovery")
        try_recovery_flush(update_state)

      :closed ->
        normal_flush(update_state)
    end
  end

  defp maybe_transition_to_half_open(state) do
    case {state.circuit_breaker.state, circuit_timeout_expired?(state)} do
      {:open, true} ->
        Logger.debug("Circuit Breaker transitioning to half_open")
        %{state | circuit_breaker: %{state.circuit_breaker | state: :half_open}}

      _ ->
        state
    end
  end

  defp get_circuit_breaker_state(state) do
    case state.circuit_breaker.state do
      :open ->
        if circuit_timeout_expired?(state) do
          :half_open
        else
          :open
        end

      other_state ->
        other_state
    end
  end

  defp circuit_timeout_expired?(state) do
    case state.circuit_breaker.next_attempt do
      nil -> false
      next_attempt -> System.monotonic_time(:millisecond) >= next_attempt
    end
  end

  defp try_recovery_flush(state) do
    case collect_batch(state.spans_table, min(10, state.config.max_buffer_size)) do
      [] ->
        {:empty, state}

      batch ->
        case send_batch(batch) do
          :ok ->
            Logger.info("Circuit Breaker recovery successful")
            new_state = reset_circuit_failure(state)
            {:ok, new_state}

          {:error, reason, failed_spans} ->
            Logger.warning("Circuit Breaker recovery failed: #{inspect(reason)}")
            failed_state = handle_send_failure(failed_spans, state)
            {:error, failed_state}
        end
    end
  end

  defp normal_flush(state) do
    case collect_batch(state.spans_table, state.config.max_buffer_size) do
      [] ->
        {:empty, state}

      batch ->
        case send_batch(batch) do
          :ok ->
            new_state = reset_circuit_failure(state)
            {:ok, new_state}

          {:error, reason, failed_spans} ->
            Logger.warning("Failed to send batch: #{inspect(reason)}")
            failed_state = handle_send_failure(failed_spans, state)
            {:error, failed_state}
        end
    end
  end

  defp collect_batch(table, max_size) do
    take_all_spans(table, max_size, [])
  end

  defp take_all_spans(_table, 0, acc), do: acc

  defp take_all_spans(table, remaining, acc) do
    case :ets.first(table) do
      :"$end_of_table" ->
        acc

      key ->
        case :ets.take(table, key) do
          [{^key, span}] ->
            take_all_spans(table, remaining - 1, [span | acc])

          [] ->
            acc
        end
    end
  end

  defp reset_circuit_failure(state) do
    %{
      state
      | circuit_breaker: %{
          state: :closed,
          failure_count: 0,
          last_failure: nil,
          next_attempt: nil
        }
    }
  end

  defp handle_send_failure(failed_batch, state) do
    new_failure_count = state.circuit_breaker.failure_count + 1
    now = System.monotonic_time(:millisecond)

    new_circuit_state =
      if new_failure_count >= state.config.circuit_breaker_threshold do
        Logger.warning("Circuit Breaker opening after #{new_failure_count} failures")
        :open
      else
        state.circuit_breaker.state
      end

    next_attempt =
      if new_circuit_state == :open do
        now +
          compute_backoff_delay(
            new_failure_count,
            state.config.backoff_base,
            state.config.circuit_breaker_max_retry_delay
          )
      else
        nil
      end

    updated_state = %{
      state
      | circuit_breaker: %{
          state: new_circuit_state,
          failure_count: new_failure_count,
          last_failure: now,
          next_attempt: next_attempt
        }
    }

    handle_failed_spans(failed_batch, updated_state)
  end

  defp compute_backoff_delay(failure_count, base_delay, max_delay \\ 30_000) do
    (base_delay * :math.pow(2, failure_count - 1))
    |> trunc()
    |> min(max_delay)
  end

  defp handle_failed_spans(spans, state) do
    case state.circuit_breaker.state do
      :open ->
        Logger.warning("Dropping #{length(spans)} spans due to Circuit Breaker")

      _ ->
        Enum.each(spans, fn span ->
          key = {System.monotonic_time(:millisecond), make_ref()}
          :ets.insert(state.spans_table, {key, span})
        end)
    end

    state
  end

  defp send_batch(spans) do
    try do
      case @agent_api_module.send_traces(spans) do
        {:ok, _response} -> :ok
        {:error, reason, failed_spans} -> {:error, reason, failed_spans}
      end
    rescue
      error ->
        {:error, error}
    end
  end
end
