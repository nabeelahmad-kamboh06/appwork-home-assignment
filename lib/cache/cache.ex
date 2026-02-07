defmodule Cache do
  @moduledoc """
  Public interface for the capped cache.

  This module provides the main API for interacting with the cache.
  It delegates to the internal GenServer while hiding implementation details.

  ## Usage

      # Start the cache
      {:ok, _pid} = Cache.start_link(cap: 1000)

      # Fetch a value
      request = %Request{url: "/api/users/1", method: :get}
      {:ok, response} = Cache.fetch(request)

  ## Supervision

      children = [
        {Cache, cap: 1000}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """

  @behaviour Cache.Behaviour

  require Logger

  @default_name Cache.Server

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Cache.Server.start_link(opts)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @impl Cache.Behaviour
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
