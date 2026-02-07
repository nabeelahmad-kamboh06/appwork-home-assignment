defmodule CacheProductionTest do
  @moduledoc """
  Production-ready tests covering error handling and edge cases.
  """
  use ExUnit.Case
  import ExUnit.CaptureLog

  defp stop_cache(name \\ Cache.Server) do
    try do
      GenServer.stop(name)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  describe "Cache.start_link/1" do
    test "starts with default options" do
      {:ok, pid} = Cache.start_link()
      assert Process.alive?(pid)
      stop_cache()
    end

    test "starts with custom name" do
      {:ok, pid} = Cache.start_link(name: :custom_cache)
      assert Process.alive?(pid)
      stop_cache(:custom_cache)
    end

    test "returns error for invalid capacity" do
      assert {:error, {:invalid_cap, _}} = Cache.start_link(cap: 0)
      assert {:error, {:invalid_cap, _}} = Cache.start_link(cap: -1)
    end
  end

  describe "Cache.fetch/2 - Error Handling" do
    setup do
      {:ok, _pid} = Cache.start_link(cap: 10)
      on_exit(fn -> stop_cache() end)
      :ok
    end

    test "returns error for invalid request" do
      invalid_request = %Request{url: "", method: :get}

      capture_log(fn ->
        assert {:error, {:invalid_request, _}} = Cache.fetch(invalid_request)
      end)
    end

    test "returns error when cache not running" do
      stop_cache()
      request = %Request{url: "/api/test", method: :get}

      capture_log(fn ->
        assert {:error, :cache_not_running} = Cache.fetch(request)
      end)
    end
  end

  describe "Multiple Named Caches" do
    test "can run multiple independent caches" do
      {:ok, _} = Cache.start_link(cap: 10, name: :cache_a)
      {:ok, _} = Cache.start_link(cap: 10, name: :cache_b)

      on_exit(fn ->
        stop_cache(:cache_a)
        stop_cache(:cache_b)
      end)

      request = %Request{url: "/api/test", method: :get}

      # Fetch in cache_a
      {:ok, _} = Cache.fetch(request, name: :cache_a)

      # Should be a miss in cache_b
      {elapsed, _} = :timer.tc(fn -> Cache.fetch(request, name: :cache_b) end)
      assert elapsed >= 100_000

      # Should be a hit in cache_a
      {elapsed_a, _} = :timer.tc(fn -> Cache.fetch(request, name: :cache_a) end)
      assert elapsed_a < 10_000
    end
  end

  describe "Edge Cases" do
    setup do
      {:ok, _pid} = Cache.start_link(cap: 3)
      on_exit(fn -> stop_cache() end)
      :ok
    end

    test "handles rapid sequential requests" do
      request = %Request{url: "/api/rapid", method: :get}

      # Rapid fire 100 requests
      results = for _ <- 1..100 do
        Cache.fetch(request)
      end

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "handles large payloads" do
      request = %Request{
        url: "/api/large",
        method: :post,
        body: String.duplicate("x", 10_000)
      }

      {:ok, response} = Cache.fetch(request)
      assert response.payload.url == "/api/large"
    end

    test "handles special characters in URL" do
      request = %Request{url: "/api/users?name=John%20Doe&id=123", method: :get}
      {:ok, response} = Cache.fetch(request)
      assert response.payload.url =~ "John%20Doe"
    end

    test "handles unicode in body" do
      request = %Request{
        url: "/api/unicode",
        method: :post,
        body: %{name: "日本語", emoji: "🎉"}
      }

      {:ok, response} = Cache.fetch(request)
      assert response.payload.url == "/api/unicode"
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = Cache.child_spec(cap: 100)

      assert spec.id == Cache
      assert spec.start == {Cache, :start_link, [[cap: 100]]}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end
  end
end
