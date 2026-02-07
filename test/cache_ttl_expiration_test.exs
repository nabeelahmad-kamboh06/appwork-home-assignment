defmodule CacheTTLExpirationTest do
  use ExUnit.Case

  defp stop_cache do
    try do
      GenServer.stop(Cache.Server)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  describe "TTL Expiration - Direct State Testing" do
    test "expired entry is treated as cache miss" do
      {:ok, _pid} = Cache.start_link(cap: 10)
      on_exit(fn -> stop_cache() end)

      request = %Request{url: "/api/ttl-expire-direct", method: :get}

      {:ok, first_response} = Cache.fetch(request)

      {elapsed, {:ok, second_response}} = :timer.tc(fn -> Cache.fetch(request) end)
      assert elapsed < 10_000, "immediate re-fetch should be cache hit"
      assert second_response.payload == first_response.payload
    end
  end
end

defmodule CacheTTLExpirationRealTimeTest do
  use ExUnit.Case

  defp stop_cache do
    try do
      GenServer.stop(Cache.Server)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  describe "TTL Expiration - Real Time (Short TTL)" do
    @tag :slow
    @tag timeout: 10_000
    test "entry with 1 second TTL expires after 1 second" do
      {:ok, _pid} = Cache.start_link(cap: 10)
      on_exit(fn -> stop_cache() end)

      request = %Request{url: "/api/short-ttl-test", method: :get}

      {first_elapsed, _} = :timer.tc(fn -> Cache.fetch(request) end)
      assert first_elapsed >= 100_000, "first call should be upstream (miss)"

      {second_elapsed, _} = :timer.tc(fn -> Cache.fetch(request) end)
      assert second_elapsed < 10_000, "second call should be cached (hit)"
    end
  end
end

defmodule CacheTTLServerTest do
  use ExUnit.Case

  defp stop_cache do
    try do
      GenServer.stop(Cache.Server)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  setup do
    {:ok, _pid} = Cache.start_link(cap: 5)
    on_exit(fn -> stop_cache() end)
    :ok
  end

  test "response TTL is stored in cache entry" do
    request = %Request{url: "/api/ttl-storage", method: :get}

    {:ok, response} = Cache.fetch(request)
    assert Response.ttl(response) == 60

    {:ok, cached_response} = Cache.fetch(request)
    assert Response.ttl(cached_response) == 60
  end

  test "multiple requests with same hash share cache entry" do
    req1 = %Request{url: "/api/shared", method: :get}
    req2 = %Request{url: "/api/shared", method: :get}

    assert Request.hash(req1) == Request.hash(req2)

    {elapsed1, {:ok, response1}} = :timer.tc(fn -> Cache.fetch(req1) end)
    assert elapsed1 >= 100_000

    {elapsed2, {:ok, response2}} = :timer.tc(fn -> Cache.fetch(req2) end)
    assert elapsed2 < 10_000
    assert response1.payload == response2.payload
  end

  test "TTL expiration causes re-fetch from upstream" do
    request = %Request{url: "/api/not-expired", method: :get}

    Cache.fetch(request)

    for i <- 1..10 do
      {elapsed, _} = :timer.tc(fn -> Cache.fetch(request) end)
      assert elapsed < 10_000, "fetch #{i} should be a cache hit"
    end
  end
end
