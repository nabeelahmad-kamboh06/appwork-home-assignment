defmodule CacheV2Test do
  use ExUnit.Case

  defp stop_cache do
    try do
      GenServer.stop(Cache.Server)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  setup do
    {:ok, _pid} = Cache.start_link(cap: 3)
    on_exit(fn -> stop_cache() end)
    :ok
  end

  describe "V2: LRU Cache - Basic Operations" do
    test "cache miss calls upstream" do
      request = %Request{url: "/api/users/1", method: :get}

      {elapsed_us, {:ok, response}} = :timer.tc(fn -> Cache.fetch(request) end)

      assert elapsed_us >= 100_000, "should call upstream (slow)"
      assert response.payload.url == "/api/users/1"
    end

    test "cache hit avoids upstream" do
      request = %Request{url: "/api/users/2", method: :get}

      {:ok, _first} = Cache.fetch(request)

      {elapsed_us, {:ok, response}} = :timer.tc(fn -> Cache.fetch(request) end)

      assert elapsed_us < 10_000, "should be cached (fast)"
      assert response.payload.url == "/api/users/2"
    end
  end

  describe "V2: LRU Cache - Distinct Requests" do
    test "no duplicate keys in cache" do
      request = %Request{url: "/api/same", method: :get}

      Cache.fetch(request)
      Cache.fetch(request)
      Cache.fetch(request)

      {elapsed_us, _} = :timer.tc(fn -> Cache.fetch(request) end)
      assert elapsed_us < 10_000, "should still be cached"
    end

    test "distinct requests are stored separately" do
      req1 = %Request{url: "/api/1", method: :get}
      req2 = %Request{url: "/api/2", method: :get}
      req3 = %Request{url: "/api/3", method: :get}

      Cache.fetch(req1)
      Cache.fetch(req2)
      Cache.fetch(req3)

      {elapsed1, _} = :timer.tc(fn -> Cache.fetch(req1) end)
      {elapsed2, _} = :timer.tc(fn -> Cache.fetch(req2) end)
      {elapsed3, _} = :timer.tc(fn -> Cache.fetch(req3) end)

      assert elapsed1 < 10_000, "req1 should be cached"
      assert elapsed2 < 10_000, "req2 should be cached"
      assert elapsed3 < 10_000, "req3 should be cached"
    end
  end

  describe "V2: LRU Cache - Recency Updates" do
    test "re-access updates recency" do
      req1 = %Request{url: "/api/1", method: :get}
      req2 = %Request{url: "/api/2", method: :get}
      req3 = %Request{url: "/api/3", method: :get}
      req4 = %Request{url: "/api/4", method: :get}

      Cache.fetch(req1)
      Cache.fetch(req2)
      Cache.fetch(req3)

      # Re-access req1 to make it most recent
      Cache.fetch(req1)

      # Add req4, should evict req2 (least recently used)
      Cache.fetch(req4)

      # req1 should still be cached (was re-accessed)
      {elapsed1, _} = :timer.tc(fn -> Cache.fetch(req1) end)
      assert elapsed1 < 10_000, "req1 should be cached (was re-accessed)"

      # req3 should still be cached
      {elapsed3, _} = :timer.tc(fn -> Cache.fetch(req3) end)
      assert elapsed3 < 10_000, "req3 should be cached"

      # req4 should be cached
      {elapsed4, _} = :timer.tc(fn -> Cache.fetch(req4) end)
      assert elapsed4 < 10_000, "req4 should be cached"

      # req2 should have been evicted
      {elapsed2, _} = :timer.tc(fn -> Cache.fetch(req2) end)
      assert elapsed2 >= 100_000, "req2 should have been evicted"
    end
  end

  describe "V2: LRU Cache - Eviction" do
    test "least recently used entry is evicted" do
      req1 = %Request{url: "/api/1", method: :get}
      req2 = %Request{url: "/api/2", method: :get}
      req3 = %Request{url: "/api/3", method: :get}
      req4 = %Request{url: "/api/4", method: :get}

      Cache.fetch(req1)
      Cache.fetch(req2)
      Cache.fetch(req3)
      Cache.fetch(req4)

      {elapsed2, _} = :timer.tc(fn -> Cache.fetch(req2) end)
      {elapsed3, _} = :timer.tc(fn -> Cache.fetch(req3) end)
      {elapsed4, _} = :timer.tc(fn -> Cache.fetch(req4) end)

      assert elapsed2 < 10_000, "req2 should be cached"
      assert elapsed3 < 10_000, "req3 should be cached"
      assert elapsed4 < 10_000, "req4 should be cached"

      {elapsed1, _} = :timer.tc(fn -> Cache.fetch(req1) end)
      assert elapsed1 >= 100_000, "req1 should have been evicted"
    end

    test "multiple evictions work correctly" do
      req1 = %Request{url: "/api/1", method: :get}
      req2 = %Request{url: "/api/2", method: :get}
      req3 = %Request{url: "/api/3", method: :get}
      req4 = %Request{url: "/api/4", method: :get}
      req5 = %Request{url: "/api/5", method: :get}
      req6 = %Request{url: "/api/6", method: :get}

      Cache.fetch(req1)
      Cache.fetch(req2)
      Cache.fetch(req3)
      Cache.fetch(req4)
      Cache.fetch(req5)
      Cache.fetch(req6)

      {elapsed4, _} = :timer.tc(fn -> Cache.fetch(req4) end)
      {elapsed5, _} = :timer.tc(fn -> Cache.fetch(req5) end)
      {elapsed6, _} = :timer.tc(fn -> Cache.fetch(req6) end)

      assert elapsed4 < 10_000, "req4 should be cached"
      assert elapsed5 < 10_000, "req5 should be cached"
      assert elapsed6 < 10_000, "req6 should be cached"

      {elapsed1, _} = :timer.tc(fn -> Cache.fetch(req1) end)
      assert elapsed1 >= 100_000, "req1 should be evicted"
    end
  end

  describe "V2: LRU Cache - Cache Hit Never Calls Upstream" do
    test "cache hit returns same response without upstream call" do
      request = %Request{url: "/api/test", method: :get}

      {:ok, first_response} = Cache.fetch(request)

      for _ <- 1..10 do
        {elapsed, {:ok, response}} = :timer.tc(fn -> Cache.fetch(request) end)
        assert elapsed < 10_000, "should be cached"
        assert response.payload == first_response.payload, "should return same response"
      end
    end
  end
end
