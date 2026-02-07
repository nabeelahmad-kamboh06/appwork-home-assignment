defmodule Cache.Telemetry do
  @moduledoc """
  Telemetry handler for Cache events.

  This module provides utilities for attaching telemetry handlers
  to cache events for monitoring and observability.

  ## Events

  The cache emits the following telemetry events:

    * `[:cache, :fetch, :start]` - Emitted when a fetch operation begins
      * Measurements: `%{}`
      * Metadata: `%{request: Request.t()}`

    * `[:cache, :fetch, :stop]` - Emitted when a fetch operation completes
      * Measurements: `%{duration: native_time}`
      * Metadata: `%{request: Request.t()}`

    * `[:cache, :fetch, :hit]` - Emitted on cache hit
      * Measurements: `%{}`
      * Metadata: `%{hash: integer}`

    * `[:cache, :fetch, :miss]` - Emitted on cache miss
      * Measurements: `%{}`
      * Metadata: `%{hash: integer}`

    * `[:cache, :fetch, :expired]` - Emitted when accessing an expired entry
      * Measurements: `%{}`
      * Metadata: `%{hash: integer}`

    * `[:cache, :evict]` - Emitted when an entry is evicted
      * Measurements: `%{}`
      * Metadata: `%{hash: integer}`

  ## Usage

      # Attach a simple logging handler
      Cache.Telemetry.attach_default_handler()

      # Or attach custom handlers
      :telemetry.attach(
        "my-handler",
        [:cache, :fetch, :hit],
        fn event, measurements, metadata, config ->
          # Handle event
        end,
        nil
      )

  """

  require Logger

  @events [
    [:cache, :fetch, :start],
    [:cache, :fetch, :stop],
    [:cache, :fetch, :hit],
    [:cache, :fetch, :miss],
    [:cache, :fetch, :expired],
    [:cache, :evict]
  ]

  @doc """
  Returns the list of all cache telemetry events.
  """
  @spec events() :: [[atom()]]
  def events, do: @events

  @doc """
  Attaches a default logging handler to all cache events.

  This is useful for development and debugging.

  ## Options

    * `:level` - Log level (default: `:debug`)

  """
  @spec attach_default_handler(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_handler(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)

    :telemetry.attach_many(
      "cache-default-handler",
      @events,
      &handle_event/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the default handler.
  """
  @spec detach_default_handler() :: :ok | {:error, :not_found}
  def detach_default_handler do
    :telemetry.detach("cache-default-handler")
  end

  # Handler implementation
  defp handle_event([:cache, :fetch, :start], _measurements, metadata, config) do
    log(config.level, "Cache fetch starting: #{inspect(metadata.request.url)}")
  end

  defp handle_event([:cache, :fetch, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    log(config.level, "Cache fetch completed: #{inspect(metadata.request.url)} in #{duration_ms}ms")
  end

  defp handle_event([:cache, :fetch, :hit], _measurements, metadata, config) do
    log(config.level, "Cache hit: hash=#{metadata.hash}")
  end

  defp handle_event([:cache, :fetch, :miss], _measurements, metadata, config) do
    log(config.level, "Cache miss: hash=#{metadata.hash}")
  end

  defp handle_event([:cache, :fetch, :expired], _measurements, metadata, config) do
    log(config.level, "Cache entry expired: hash=#{metadata.hash}")
  end

  defp handle_event([:cache, :evict], _measurements, metadata, config) do
    log(config.level, "Cache eviction: hash=#{metadata.hash}")
  end

  defp log(:debug, msg), do: Logger.debug(msg)
  defp log(:info, msg), do: Logger.info(msg)
  defp log(:warning, msg), do: Logger.warning(msg)
  defp log(:error, msg), do: Logger.error(msg)
  defp log(_, msg), do: Logger.debug(msg)
end
