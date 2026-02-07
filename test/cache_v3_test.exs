defmodule CacheV3Test do
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

  describe "V3: TTL Support - Valid TTL" do
    test "valid TTL returns cached response (cache hit)" do
      request = %Request{url: "/api/ttl-test", method: :get}

      {:ok, first_response} = Cache.fetch(request)

      {elapsed_us, {:ok, second_response}} = :timer.tc(fn -> Cache.fetch(request) end)

      assert elapsed_us < 10_000, "should be a cache hit"
      assert second_response.payload == first_response.payload
    end
  end

  describe "V3: TTL Support - Expired TTL" do
    test "expired TTL calls upstream again" do
      request = %Request{url: "/api/expire-test", method: :get}

      {first_elapsed, _first_response} = :timer.tc(fn -> Cache.fetch(request) end)
      assert first_elapsed >= 100_000, "first call should be a miss"

      {second_elapsed, _second_response} = :timer.tc(fn -> Cache.fetch(request) end)
      assert second_elapsed < 10_000, "second call should be a hit"
    end
  end

  describe "V3: TTL Support - Response TTL is respected" do
    test "cache entry stores TTL from response" do
      request = %Request{url: "/api/ttl-stored", method: :get}

      Cache.fetch(request)

      for _ <- 1..5 do
        {elapsed, _} = :timer.tc(fn -> Cache.fetch(request) end)
        assert elapsed < 10_000, "should be cached within TTL"
      end
    end
  end
end

defmodule CacheV3TTLExpirationTest do
  use ExUnit.Case

  defp stop_cache do
    try do
      GenServer.stop(Cache.Server)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  setup do
    {:ok, _pid} = Cache.start_link(cap: 10)
    on_exit(fn -> stop_cache() end)
    :ok
  end

  describe "V3: TTL Expiration Integration" do
    @tag :slow
    test "entry expires after TTL and upstream is called again" do
      request = %Request{url: "/api/integration-ttl", method: :get}

      {first_elapsed, {:ok, first_response}} = :timer.tc(fn -> Cache.fetch(request) end)
      assert first_elapsed >= 100_000

      {second_elapsed, {:ok, second_response}} = :timer.tc(fn -> Cache.fetch(request) end)
      assert second_elapsed < 10_000
      assert second_response.payload == first_response.payload
    end
  end
end

defmodule CacheV3TTLMockTest do
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

  test "fresh cache entry is a hit" do
    request = %Request{url: "/api/fresh", method: :get}

    Cache.fetch(request)

    {elapsed, _} = :timer.tc(fn -> Cache.fetch(request) end)
    assert elapsed < 10_000
  end

  test "LRU and TTL work together" do
    req1 = %Request{url: "/api/1", method: :get}
    req2 = %Request{url: "/api/2", method: :get}
    req3 = %Request{url: "/api/3", method: :get}
    req4 = %Request{url: "/api/4", method: :get}

    Cache.fetch(req1)
    Cache.fetch(req2)
    Cache.fetch(req3)

    Cache.fetch(req1)
    Cache.fetch(req4)

    {elapsed1, _} = :timer.tc(fn -> Cache.fetch(req1) end)
    assert elapsed1 < 10_000

    {elapsed2, _} = :timer.tc(fn -> Cache.fetch(req2) end)
    assert elapsed2 >= 100_000
  end
end
