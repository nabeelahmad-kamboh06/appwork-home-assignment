defmodule Cache.Server do
  @moduledoc """
  GenServer implementing the LRU + TTL cache.

  This module is internal - use the `Cache` module for the public API.

  ## State Structure

  The server maintains the following state:

      %{
        cap: integer(),           # Maximum number of entries
        store: %{hash => entry},  # Hash -> Entry mapping
        lru: [hash]               # LRU list (most recent first)
      }

  ## Entry Structure

      %{
        response: Response.t(),
        inserted_at: integer(),   # Unix timestamp (seconds)
        ttl: integer()            # TTL in seconds
      }

  ## Telemetry

  Emits telemetry events for observability:

    * `[:cache, :fetch, :start]`
    * `[:cache, :fetch, :stop]`
    * `[:cache, :fetch, :hit]`
    * `[:cache, :fetch, :miss]`
    * `[:cache, :fetch, :expired]`
    * `[:cache, :evict]`

  """

  use GenServer

  require Logger

  @default_cap 100
  @default_name Cache.Server

  # Type definitions
  @type hash :: non_neg_integer()
  @type entry :: %{
          response: Response.t(),
          inserted_at: integer(),
          ttl: non_neg_integer()
        }
  @type state :: %{
          cap: pos_integer(),
          store: %{optional(hash()) => entry()},
          lru: [hash()]
        }

  # --- Client API ---

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    cap = get_opt(opts, :cap, @default_cap)
    name = get_opt(opts, :name, @default_name)

    # Validate capacity
    if cap < 1 do
      {:error, {:invalid_cap, "capacity must be at least 1"}}
    else
      GenServer.start_link(__MODULE__, cap, name: name)
    end
  end

  @doc false
  @spec fetch(Request.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def fetch(%Request{} = request, opts \\ []) do
    name = get_opt(opts, :name, @default_name)
    timeout = get_opt(opts, :timeout, 5000)

    try do
      GenServer.call(name, {:fetch, request}, timeout)
    catch
      :exit, {:noproc, _} ->
        Logger.error("Cache server not running: #{inspect(name)}")
        {:error, :cache_not_running}

      :exit, {:timeout, _} ->
        Logger.error("Cache fetch timeout after #{timeout}ms")
        {:error, :timeout}
    end
  end

  # --- Server Callbacks ---

  @impl GenServer
  def init(cap) do
    Logger.info("Cache server starting with capacity: #{cap}")

    state = %{
      cap: cap,
      store: %{},
      lru: []
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:fetch, request}, _from, state) do
    start_time = System.monotonic_time()
    emit_telemetry([:cache, :fetch, :start], %{}, %{request: request})

    hash = Request.hash(request)
    {result, new_state} = do_fetch(hash, request, state)

    duration = System.monotonic_time() - start_time
    emit_telemetry([:cache, :fetch, :stop], %{duration: duration}, %{request: request})

    {:reply, result, new_state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    size = map_size(state.store)
    cap = state.cap
    utilization = if cap > 0, do: Float.round(size / cap * 100, 2), else: 0.0

    stats = %{
      size: size,
      cap: cap,
      utilization: utilization,
      available: cap - size
    }

    {:reply, {:ok, stats}, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Cache server terminating: #{inspect(reason)}, entries: #{map_size(state.store)}")
    :ok
  end

  # --- Private Functions ---

  defp do_fetch(hash, request, state) do
    now = System.system_time(:second)

    case lookup(hash, state.store) do
      {:hit, entry} ->
        if expired?(entry, now) do
          # Entry expired - emit telemetry, remove, fetch fresh
          emit_telemetry([:cache, :fetch, :expired], %{}, %{hash: hash})
          Logger.debug("Cache entry expired: #{inspect(request.url)}")

          state_after_removal = remove_entry(state, hash)
          fetch_and_insert(request, hash, state_after_removal)
        else
          # Valid cache hit
          emit_telemetry([:cache, :fetch, :hit], %{}, %{hash: hash})
          Logger.debug("Cache hit: #{inspect(request.url)}")

          new_state = touch_lru(state, hash)
          {{:ok, entry.response}, new_state}
        end

      :miss ->
        # Cache miss - fetch from upstream
        emit_telemetry([:cache, :fetch, :miss], %{}, %{hash: hash})
        Logger.debug("Cache miss: #{inspect(request.url)}")

        fetch_and_insert(request, hash, state)
    end
  end

  defp lookup(hash, store) do
    case Map.get(store, hash) do
      nil -> :miss
      entry -> {:hit, entry}
    end
  end

  defp expired?(entry, now) do
    now - entry.inserted_at > entry.ttl
  end

  defp fetch_and_insert(request, hash, state) do
    case Upstream.fetch(request) do
      {:ok, response} ->
        new_state = insert_and_evict(state, hash, response)
        {{:ok, response}, new_state}

      {:error, reason} = error ->
        Logger.error("Upstream fetch failed: #{inspect(reason)}")
        {error, state}
    end
  end

  defp remove_entry(state, hash) do
    new_store = Map.delete(state.store, hash)
    new_lru = List.delete(state.lru, hash)
    %{state | store: new_store, lru: new_lru}
  end

  defp touch_lru(state, hash) do
    new_lru = [hash | List.delete(state.lru, hash)]
    %{state | lru: new_lru}
  end

  defp insert_and_evict(state, hash, response) do
    entry = %{
      response: response,
      inserted_at: System.system_time(:second),
      ttl: Response.ttl(response)
    }

    # Insert into store and prepend to LRU (remove hash first if it exists to avoid duplicates)
    new_store = Map.put(state.store, hash, entry)
    new_lru = [hash | List.delete(state.lru, hash)]

    new_state = %{state | store: new_store, lru: new_lru}

    # Evict if over capacity
    evict_if_needed(new_state)
  end

  # Optimized: Use map_size(store) instead of length(lru) - O(1) vs O(n)
  defp evict_if_needed(%{cap: cap, lru: lru, store: store} = state) when map_size(store) > cap do
    # Get the least recently used hash (last in list)
    # Note: List.last is O(n), but eviction is rare compared to hits
    lru_hash = List.last(lru)

    emit_telemetry([:cache, :evict], %{}, %{hash: lru_hash})
    Logger.debug("Evicting LRU entry: #{lru_hash}")

    # Remove from store and LRU
    new_store = Map.delete(store, lru_hash)
    new_lru = List.delete(lru, lru_hash)

    %{state | store: new_store, lru: new_lru}
  end

  defp evict_if_needed(state), do: state

  defp get_opt(opts, key, default) do
    Keyword.get(opts, key, Application.get_env(:lru_cache, Cache, []) |> Keyword.get(key, default))
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  rescue
    # Telemetry not installed - silently ignore
    UndefinedFunctionError -> :ok
  end
end
