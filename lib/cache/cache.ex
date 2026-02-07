defmodule Cache do
  @moduledoc """
  Public interface for the LRU + TTL cache.

  This module provides the main API for interacting with the cache.
  It delegates to the internal GenServer while hiding implementation details.

  ## Features

    * LRU (Least Recently Used) eviction policy
    * TTL (Time-To-Live) support with lazy expiration
    * Thread-safe operations via GenServer serialization
    * Configurable capacity
    * Telemetry integration for observability

  ## Usage

      # Start the cache (typically done in your application supervisor)
      {:ok, _pid} = Cache.start_link(cap: 1000)

      # Fetch a value
      request = %Request{url: "/api/users/1", method: :get}
      {:ok, response} = Cache.fetch(request)

  ## Configuration

  The cache can be configured via application config:

      config :lru_cache, Cache,
        cap: 1000,
        name: Cache.Server

  Or via options passed to `start_link/1`:

      Cache.start_link(cap: 500, name: :my_cache)

  ## Supervision

  The cache is designed to be supervised. Add it to your supervision tree:

      children = [
        {Cache, cap: 1000}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  ## Telemetry Events

  The cache emits the following telemetry events:

    * `[:cache, :fetch, :start]` - When a fetch begins
    * `[:cache, :fetch, :stop]` - When a fetch completes
    * `[:cache, :fetch, :hit]` - On cache hit
    * `[:cache, :fetch, :miss]` - On cache miss
    * `[:cache, :fetch, :expired]` - When TTL expired
    * `[:cache, :evict]` - When an entry is evicted

  To enable logging of these events:

      Cache.Telemetry.attach_default_handler(level: :info)

  """

  @behaviour Cache.Behaviour

  require Logger

  @default_cap 100
  @default_name Cache.Server

  @type start_opts :: [
          cap: pos_integer(),
          name: atom()
        ]

  @doc """
  Starts the cache server.

  ## Options

    * `:cap` - Maximum number of entries (default: #{@default_cap})
    * `:name` - Process name (default: `#{inspect(@default_name)}`)

  ## Returns

    * `{:ok, pid}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> {:ok, pid} = Cache.start_link(cap: 100)
      iex> is_pid(pid)
      true

  """
  @spec start_link(start_opts()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Cache.Server.start_link(opts)
  end

  @doc """
  Returns a child specification for supervision.

  This allows the cache to be added directly to a supervision tree.

  ## Examples

      children = [
        {Cache, cap: 1000}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  """
  @spec child_spec(start_opts()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Fetches a response for the given request.

  If the request is cached and not expired, returns the cached response.
  Otherwise, fetches from upstream, caches the result, and returns it.

  ## Parameters

    * `request` - A `Request` struct
    * `opts` - Optional keyword list:
      * `:name` - Server name (default: `#{inspect(@default_name)}`)
      * `:timeout` - GenServer call timeout in ms (default: 5000)

  ## Returns

    * `{:ok, Response.t()}` - On success
    * `{:error, reason}` - On failure

  ## Examples

      iex> request = %Request{url: "/api/users", method: :get}
      iex> {:ok, response} = Cache.fetch(request)
      iex> response.payload.url
      "/api/users"

  """
  @impl Cache.Behaviour
  @spec fetch(Request.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def fetch(%Request{} = request, opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    timeout = Keyword.get(opts, :timeout, 5000)

    case Request.validate(request) do
      :ok ->
        Cache.Server.fetch(request, name: name, timeout: timeout)

      {:error, reason} ->
        Logger.warning("Invalid request: #{reason}")
        {:error, {:invalid_request, reason}}
    end
  end

  @spec stats(keyword()) :: {:ok, map()} | {:error, term()}
  def stats(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.call(name, :stats)
  end
end
