defmodule Request do
  @moduledoc """
  Represents a cacheable HTTP-like request.

  The `Request` struct encapsulates all the information needed to uniquely
  identify a cacheable request. The `hash/1` function generates a deterministic
  hash that serves as the cache key.

  ## Fields

    * `:url` - The request URL (required)
    * `:method` - The HTTP method as an atom, e.g., `:get`, `:post` (required)
    * `:headers` - Optional map of request headers
    * `:body` - Optional request body (for POST/PUT/PATCH requests)

  ## Examples

      iex> request = %Request{url: "/api/users", method: :get}
      iex> Request.hash(request)
      123456789

      iex> request = %Request{
      ...>   url: "/api/users",
      ...>   method: :post,
      ...>   headers: %{"content-type" => "application/json"},
      ...>   body: %{name: "Alice"}
      ...> }
      iex> Request.hash(request)
      987654321

  """

  @enforce_keys [:url, :method]
  defstruct [:url, :method, :headers, :body]

  @type t :: %__MODULE__{
          url: String.t(),
          method: http_method(),
          headers: headers() | nil,
          body: body() | nil
        }

  @type http_method :: :get | :post | :put | :patch | :delete | :head | :options
  @type headers :: %{optional(String.t()) => String.t()}
  @type body :: map() | String.t() | binary() | nil

  @doc """
  Computes a deterministic hash for the request.

  The hash is based on the combination of url, method, headers, and body.
  Two requests with identical fields will always produce the same hash.

  ## Parameters

    * `request` - A `Request` struct

  ## Returns

    * An integer hash value

  ## Examples

      iex> req1 = %Request{url: "/api/users", method: :get}
      iex> req2 = %Request{url: "/api/users", method: :get}
      iex> Request.hash(req1) == Request.hash(req2)
      true

      iex> req1 = %Request{url: "/api/users", method: :get}
      iex> req2 = %Request{url: "/api/posts", method: :get}
      iex> Request.hash(req1) == Request.hash(req2)
      false

  """
  @spec hash(t()) :: non_neg_integer()
  def hash(%__MODULE__{} = request) do
    :erlang.phash2({
      request.url,
      request.method,
      normalize_headers(request.headers),
      request.body
    })
  end

  @doc """
  Validates a request struct.

  ## Parameters

    * `request` - A `Request` struct to validate

  ## Returns

    * `:ok` if valid
    * `{:error, reason}` if invalid

  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{url: url, method: method}) do
    cond do
      not is_binary(url) or url == "" ->
        {:error, "url must be a non-empty string"}

      method not in [:get, :post, :put, :patch, :delete, :head, :options] ->
        {:error, "method must be a valid HTTP method atom"}

      true ->
        :ok
    end
  end

  # Normalize headers for consistent hashing
  # Sorts headers by key to ensure order doesn't affect hash
  defp normalize_headers(nil), do: nil

  defp normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), v} end)
    |> Enum.sort_by(fn {k, _v} -> k end)
  end
end
