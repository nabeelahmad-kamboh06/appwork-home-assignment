defmodule Response do
  @moduledoc """
  Represents a response from the cache or upstream service.

  The `Response` struct contains the actual payload data and metadata
  about how long the response should be cached (TTL).

  ## Fields

    * `:payload` - The response data (required)
    * `:ttl` - Time-to-live in seconds (default: 60)
    * `:metadata` - Optional metadata map for debugging/tracing

  ## Examples

      iex> response = %Response{payload: %{user: "Alice"}}
      iex> Response.ttl(response)
      60

      iex> response = %Response{payload: %{user: "Alice"}, ttl: 300}
      iex> Response.ttl(response)
      300

  """

  @enforce_keys [:payload]
  defstruct [:payload, :metadata, ttl: 60]

  @type t :: %__MODULE__{
          payload: payload(),
          ttl: non_neg_integer(),
          metadata: metadata() | nil
        }

  @type payload :: map() | String.t() | binary() | list()
  @type metadata :: %{optional(atom()) => term()}

  @doc """
  Returns the TTL (time-to-live) in seconds for this response.

  This function is required by V3 of the cache specifications.

  ## Parameters

    * `response` - A `Response` struct

  ## Returns

    * TTL as a non-negative integer (seconds)

  ## Examples

      iex> response = %Response{payload: "data", ttl: 120}
      iex> Response.ttl(response)
      120

  """
  @spec ttl(t()) :: non_neg_integer()
  def ttl(%__MODULE__{ttl: ttl}), do: ttl
end
