defmodule Upstream do
  @moduledoc """
  Simulates an upstream service that provides responses.

  In a production environment, this module would be replaced with
  actual HTTP client calls to external services. The current implementation
  simulates network latency and returns mock responses.

  ## Configuration

  The following options can be configured via application config:

      config :lru_cache, Upstream,
        default_latency_ms: 100,
        default_ttl: 60

  ## Examples

      iex> request = %Request{url: "/api/users", method: :get}
      iex> {:ok, response} = Upstream.fetch(request)
      iex> response.payload.url
      "/api/users"

  """

  require Logger

  @default_latency_ms 1000
  @default_ttl 40

  @type fetch_opts :: [
          latency_ms: non_neg_integer(),
          ttl: non_neg_integer(),
          simulate_error: boolean()
        ]

  @doc """
  Fetches a response from the upstream service.

  Simulates network latency with a configurable delay. In production,
  this would make actual HTTP requests to external services.

  ## Parameters

    * `request` - A `Request` struct
    * `opts` - Keyword list of options:
      * `:latency_ms` - Simulated latency in milliseconds (default: #{@default_latency_ms})
      * `:ttl` - TTL for the response in seconds (default: #{@default_ttl})
      * `:simulate_error` - If true, simulates an error response (default: false)

  ## Returns

    * `{:ok, Response.t()}` - On success
    * `{:error, reason}` - On failure

  ## Examples

      iex> request = %Request{url: "/api/test", method: :get}
      iex> {:ok, response} = Upstream.fetch(request, latency_ms: 0)
      iex> response.payload.url
      "/api/test"

      iex> request = %Request{url: "/api/test", method: :get}
      iex> {:error, :simulated_error} = Upstream.fetch(request, simulate_error: true)

  """
  @spec fetch(Request.t(), fetch_opts()) :: {:ok, Response.t()} | {:error, term()}
  def fetch(%Request{} = request, opts \\ []) do
    latency_ms = Keyword.get(opts, :latency_ms, get_config(:default_latency_ms, @default_latency_ms))
    ttl = Keyword.get(opts, :ttl, get_config(:default_ttl, @default_ttl))
    simulate_error = Keyword.get(opts, :simulate_error, false)

    # Log upstream request for observability
    Logger.debug("Upstream fetch: #{request.method} #{request.url}")

    # Simulate network latency
    if latency_ms > 0 do
      Process.sleep(latency_ms)
    end

    # Simulate error if requested
    if simulate_error do
      Logger.warning("Upstream simulated error for: #{request.url}")
      {:error, :simulated_error}
    else
      response = %Response{
        payload: %{
          url: request.url,
          method: request.method,
          data: "Response for #{request.method} #{request.url}",
          fetched_at: DateTime.utc_now()
        },
        ttl: ttl,
        metadata: %{source: :upstream}
      }

      {:ok, response}
    end
  end

  # Get configuration value with fallback
  defp get_config(key, default) do
    Application.get_env(:lru_cache, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
