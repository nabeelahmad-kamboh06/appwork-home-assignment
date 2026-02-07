defmodule Cache.Behaviour do
  @moduledoc """
  Defines the cache behaviour contract.

  Any cache implementation must implement the `fetch/1` callback.
  This allows for different cache implementations (e.g., in-memory, distributed)
  while maintaining a consistent interface.

  ## Example Implementation

      defmodule MyCache do
        @behaviour Cache.Behaviour

        @impl Cache.Behaviour
        def fetch(request) do
          # Implementation here
        end
      end
  """

  @doc """
  Fetches a response for the given request.

  Returns the cached response if available and valid (not expired),
  otherwise fetches from upstream and caches the result.

  ## Parameters

    * `request` - A `Request` struct containing the request details

  ## Returns

    * `{:ok, Response.t()}` - On successful fetch (cache hit or upstream success)
    * `{:error, reason}` - On failure

  ## Examples

      iex> request = %Request{url: "/api/users", method: :get}
      iex> Cache.fetch(request)
      {:ok, %Response{payload: %{...}, ttl: 60}}

  """
  @callback fetch(request :: Request.t()) :: {:ok, Response.t()} | {:error, term()}
end
