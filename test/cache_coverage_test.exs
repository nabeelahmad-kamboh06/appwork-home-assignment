defmodule CacheCoverageTest do
  @moduledoc """
  Additional coverage tests for Cache, Cache.Server, and LruCache.Application
  to meet the 90% coverage threshold.
  """
  use ExUnit.Case
  import ExUnit.CaptureLog

  require Logger

  defp stop_cache(name \\ Cache.Server) do
    try do
      GenServer.stop(name)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  describe "Cache.stats/1" do
    test "returns stats for an empty cache" do
      {:ok, _pid} = Cache.start_link(cap: 10)
      on_exit(fn -> stop_cache() end)

      {:ok, stats} = Cache.stats()

      assert stats.size == 0
      assert stats.cap == 10
      assert stats.utilization == 0.0
      assert stats.available == 10
    end

    test "returns stats after inserting entries" do
      {:ok, _pid} = Cache.start_link(cap: 10)
      on_exit(fn -> stop_cache() end)

      Cache.fetch(%Request{url: "/api/stats-1", method: :get})
      Cache.fetch(%Request{url: "/api/stats-2", method: :get})

      {:ok, stats} = Cache.stats()

      assert stats.size == 2
      assert stats.cap == 10
      assert stats.utilization == 20.0
      assert stats.available == 8
    end

    test "returns stats with custom name" do
      {:ok, _pid} = Cache.start_link(cap: 5, name: :stats_cache)
      on_exit(fn -> stop_cache(:stats_cache) end)

      {:ok, stats} = Cache.stats(name: :stats_cache)
      assert stats.cap == 5
    end
  end

  describe "Cache.Server.terminate/2" do
    test "terminate is called when server is stopped" do
      previous_level = Logger.level()
      Logger.configure(level: :info)

      {:ok, pid} = Cache.start_link(cap: 5)

      # Add an entry so terminate logs a non-zero entry count
      Cache.fetch(%Request{url: "/api/terminate-test", method: :get})

      log =
        capture_log([level: :info], fn ->
          GenServer.stop(pid, :normal)
          # Small wait for log to flush
          Process.sleep(50)
        end)

      Logger.configure(level: previous_level)
      assert log =~ "Cache server terminating"
    end
  end

  describe "Cache.Server.fetch/2 - error branches" do
    test "returns error when server is not running (noproc)" do
      log =
        capture_log(fn ->
          result = Cache.Server.fetch(%Request{url: "/api/noproc", method: :get}, name: :nonexistent_cache)
          assert {:error, :cache_not_running} = result
        end)

      assert log =~ "Cache server not running"
    end

    test "returns error on timeout" do
      {:ok, _pid} = Cache.start_link(cap: 5)
      on_exit(fn -> stop_cache() end)

      # Use a very short timeout - the upstream sleep (100ms in test config) will exceed it
      log =
        capture_log(fn ->
          result =
            Cache.Server.fetch(
              %Request{url: "/api/timeout-test", method: :get},
              name: Cache.Server,
              timeout: 1
            )

          assert {:error, :timeout} = result
        end)

      assert log =~ "Cache fetch timeout"
    end
  end

  describe "LruCache.Application - auto_start branch" do
    test "starts cache server when auto_start is true" do
      # First stop the existing application supervisor
      Supervisor.stop(LruCache.Supervisor)
      # Small wait for cleanup
      Process.sleep(50)

      # Set auto_start to true
      original_auto = Application.get_env(:lru_cache, :auto_start)
      Application.put_env(:lru_cache, :auto_start, true)
      Application.put_env(:lru_cache, :cap, 50)

      previous_level = Logger.level()
      Logger.configure(level: :info)

      on_exit(fn ->
        # Restore original settings
        Application.put_env(:lru_cache, :auto_start, original_auto || false)
        Logger.configure(level: previous_level)
        # Restart the application supervisor with default config (auto_start: false)
        LruCache.Application.start(:normal, [])
      end)

      log =
        capture_log([level: :info], fn ->
          {:ok, sup_pid} = LruCache.Application.start(:normal, [])
          assert Process.alive?(sup_pid)

          # The cache should be running - verify by calling stats
          {:ok, stats} = Cache.stats()
          assert stats.cap == 50

          # Stop the supervisor for cleanup
          Supervisor.stop(sup_pid)
          Process.sleep(50)
        end)

      assert log =~ "Starting LRU Cache application"
    end
  end

  describe "Cache.fetch/2 with custom timeout option" do
    test "accepts timeout option" do
      {:ok, _pid} = Cache.start_link(cap: 5)
      on_exit(fn -> stop_cache() end)

      request = %Request{url: "/api/custom-timeout", method: :get}

      # Should succeed with a generous timeout
      {:ok, response} = Cache.fetch(request, timeout: 10_000)
      assert response.payload.url == "/api/custom-timeout"
    end
  end
end
