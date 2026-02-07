defmodule Cache.Server do
  @moduledoc """
  GenServer implementing the LRU cache.

  Stores the last CAP distinct request-response pairs. When a cached request
  is accessed again, its recency is updated (moved to front of LRU list).
  The least recently used entry is evicted when capacity is exceeded.

  ## State Structure

      %{
        cap: integer(),
        store: %{hash => entry},
        lru: [hash]               # Most recent first
      }
  """

  use GenServer

  require Logger

  @default_cap 100
  @default_name Cache.Server

  # --- Client API ---

  @doc false
  def start_link(opts \\ []) do
    cap = get_opt(opts, :cap, @default_cap)
    name = get_opt(opts, :name, @default_name)

    if cap < 1 do
      {:error, {:invalid_cap, "capacity must be at least 1"}}
    else
      GenServer.start_link(__MODULE__, cap, name: name)
    end
  end

  @doc false
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
    hash = Request.hash(request)
    {result, new_state} = do_fetch(hash, request, state)
    {:reply, result, new_state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    size = map_size(state.store)

    stats = %{
      size: size,
      cap: state.cap,
      utilization: if(state.cap > 0, do: Float.round(size / state.cap * 100, 2), else: 0.0),
      available: state.cap - size
    }

    {:reply, {:ok, stats}, state}
  end

  # --- Private Functions ---

  defp do_fetch(hash, request, state) do
    case Map.get(state.store, hash) do
      nil ->
        # Cache miss - fetch from upstream
        Logger.debug("Cache miss: #{inspect(request.url)}")
        fetch_and_insert(request, hash, state)

      entry ->
        # Cache hit - update recency (LRU touch)
        Logger.debug("Cache hit: #{inspect(request.url)}")
        new_state = touch_lru(state, hash)
        {{:ok, entry.response}, new_state}
    end
  end

  # Move hash to front of LRU list (most recently used)
  defp touch_lru(state, hash) do
    new_lru = [hash | List.delete(state.lru, hash)]
    %{state | lru: new_lru}
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

  defp insert_and_evict(state, hash, response) do
    entry = %{response: response}

    new_store = Map.put(state.store, hash, entry)
    # Prepend to LRU list (most recent first), deduplicate
    new_lru = [hash | List.delete(state.lru, hash)]

    new_state = %{state | store: new_store, lru: new_lru}
    evict_if_needed(new_state)
  end

  # Evict least recently used entry (last in LRU list) when over capacity
  defp evict_if_needed(%{cap: cap, lru: lru, store: store} = state) when map_size(store) > cap do
    lru_hash = List.last(lru)
    Logger.debug("Evicting LRU entry: #{lru_hash}")
    %{state | store: Map.delete(store, lru_hash), lru: List.delete(lru, lru_hash)}
  end

  defp evict_if_needed(state), do: state

  defp get_opt(opts, key, default) do
    Keyword.get(opts, key, Application.get_env(:lru_cache, Cache, []) |> Keyword.get(key, default))
  end
end
