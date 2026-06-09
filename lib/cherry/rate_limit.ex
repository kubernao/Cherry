defmodule Cherry.RateLimit do
  @moduledoc false

  use GenServer

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  def allow?(key, limit, window_ms)
      when is_integer(limit) and limit > 0 and is_integer(window_ms) and window_ms > 0 do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, count, reset_at}] when reset_at > now and count >= limit ->
        false

      [{^key, count, reset_at}] when reset_at > now ->
        :ets.insert(@table, {key, count + 1, reset_at})
        true

      _ ->
        :ets.insert(@table, {key, 1, now + window_ms})
        true
    end
  end

  def reset(key), do: :ets.delete(@table, key)
end
