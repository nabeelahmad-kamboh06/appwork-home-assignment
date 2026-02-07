defmodule CacheTelemetryTest do
  @moduledoc """
  Tests for the Cache.Telemetry module to ensure telemetry events
  are properly emitted, handled, and logged.
  """
  use ExUnit.Case
  import ExUnit.CaptureLog

  require Logger

  defp stop_cache do
    try do
      GenServer.stop(Cache.Server)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  describe "events/0" do
    test "returns all cache telemetry events" do
      events = Cache.Telemetry.events()

      assert [:cache, :fetch, :start] in events
      assert [:cache, :fetch, :stop] in events
      assert [:cache, :fetch, :hit] in events
      assert [:cache, :fetch, :miss] in events
      assert [:cache, :fetch, :expired] in events
      assert [:cache, :evict] in events
      assert length(events) == 6
    end
  end

  describe "attach_default_handler/1 and detach_default_handler/0" do
    test "attaches and detaches the default handler" do
      assert :ok = Cache.Telemetry.attach_default_handler()
      # Attaching again should return error
      assert {:error, :already_exists} = Cache.Telemetry.attach_default_handler()
      # Detach
      assert :ok = Cache.Telemetry.detach_default_handler()
    end

    test "detach returns error when not attached" do
      assert {:error, :not_found} = Cache.Telemetry.detach_default_handler()
    end

    test "attaches with custom log level" do
      assert :ok = Cache.Telemetry.attach_default_handler(level: :info)
      Cache.Telemetry.detach_default_handler()
    end
  end

  describe "handle_event/4 - telemetry event logging" do
    setup do
      # Temporarily lower Logger level so debug/info messages are captured
      previous_level = Logger.level()
      Logger.configure(level: :debug)

      {:ok, _pid} = Cache.start_link(cap: 5)

      on_exit(fn ->
        Cache.Telemetry.detach_default_handler()
        stop_cache()
        Logger.configure(level: previous_level)
      end)

      :ok
    end

    test "logs cache fetch start and stop events" do
      Cache.Telemetry.attach_default_handler(level: :info)

      log =
        capture_log([level: :info], fn ->
          request = %Request{url: "/api/telemetry-test", method: :get}
          Cache.fetch(request)
        end)

      assert log =~ "Cache fetch starting"
      assert log =~ "/api/telemetry-test"
      assert log =~ "Cache fetch completed"
    end

    test "logs cache hit event" do
      Cache.Telemetry.attach_default_handler(level: :info)

      request = %Request{url: "/api/hit-test", method: :get}
      # First fetch - miss
      Cache.fetch(request)

      # Second fetch - hit
      log =
        capture_log([level: :info], fn ->
          Cache.fetch(request)
        end)

      assert log =~ "Cache hit"
    end

    test "logs cache miss event" do
      Cache.Telemetry.attach_default_handler(level: :info)

      log =
        capture_log([level: :info], fn ->
          request = %Request{url: "/api/miss-test", method: :get}
          Cache.fetch(request)
        end)

      assert log =~ "Cache miss"
    end

    test "logs cache eviction event" do
      Cache.Telemetry.attach_default_handler(level: :info)

      # Fill cache to capacity (cap: 5)
      for i <- 1..5 do
        Cache.fetch(%Request{url: "/api/evict-#{i}", method: :get})
      end

      # This should trigger an eviction
      log =
        capture_log([level: :info], fn ->
          Cache.fetch(%Request{url: "/api/evict-overflow", method: :get})
        end)

      assert log =~ "Cache eviction"
    end

    test "logs with debug level by default" do
      Cache.Telemetry.attach_default_handler()

      log =
        capture_log([level: :debug], fn ->
          request = %Request{url: "/api/debug-test", method: :get}
          Cache.fetch(request)
        end)

      assert log =~ "Cache fetch starting"
    end

    test "logs with warning level" do
      Cache.Telemetry.attach_default_handler(level: :warning)

      log =
        capture_log([level: :warning], fn ->
          request = %Request{url: "/api/warn-test", method: :get}
          Cache.fetch(request)
        end)

      assert log =~ "Cache fetch starting"
    end

    test "logs with error level" do
      Cache.Telemetry.attach_default_handler(level: :error)

      log =
        capture_log([level: :error], fn ->
          request = %Request{url: "/api/error-level-test", method: :get}
          Cache.fetch(request)
        end)

      assert log =~ "Cache fetch starting"
    end

    test "logs with fallback level for unknown level" do
      Cache.Telemetry.attach_default_handler(level: :unknown_level)

      log =
        capture_log([level: :debug], fn ->
          request = %Request{url: "/api/fallback-test", method: :get}
          Cache.fetch(request)
        end)

      assert log =~ "Cache fetch starting"
    end
  end
end
