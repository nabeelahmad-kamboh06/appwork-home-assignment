defmodule CacheV1Test do
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

  describe "V1: Basic Cache (Capped Capacity)" do
    test "cache miss calls upstream" do
      request = %Request{url: "/api/users/1", method: :get}

      {elapsed_us, {:ok, response}} = :timer.tc(fn -> Cache.fetch(request) end)

      assert elapsed_us >= 100_000, "should call upstream (slow)"
      assert response.payload.url == "/api/users/1"
    end

    test "cache hit avoids upstream" do
      request = %Request{url: "/api/users/2", method: :get}

      # First call - miss
      {:ok, _first_response} = Cache.fetch(request)

      # Second call - hit
      {elapsed_us, {:ok, second_response}} = :timer.tc(fn -> Cache.fetch(request) end)

      assert elapsed_us < 10_000, "should be cached (fast)"
      assert second_response.payload.url == "/api/users/2"
    end

    test "oldest entry evicted when capacity exceeded" do
      req1 = %Request{url: "/api/1", method: :get}
      req2 = %Request{url: "/api/2", method: :get}
      req3 = %Request{url: "/api/3", method: :get}
      req4 = %Request{url: "/api/4", method: :get}

      Cache.fetch(req1)
      Cache.fetch(req2)
      Cache.fetch(req3)
      Cache.fetch(req4)

      # req2, req3, req4 should be cached
      {elapsed_req2, _} = :timer.tc(fn -> Cache.fetch(req2) end)
      {elapsed_req3, _} = :timer.tc(fn -> Cache.fetch(req3) end)
      {elapsed_req4, _} = :timer.tc(fn -> Cache.fetch(req4) end)

      assert elapsed_req2 < 10_000, "req2 should be cached"
      assert elapsed_req3 < 10_000, "req3 should be cached"
      assert elapsed_req4 < 10_000, "req4 should be cached"

      # req1 should be evicted
      {elapsed_req1, _} = :timer.tc(fn -> Cache.fetch(req1) end)
      assert elapsed_req1 >= 100_000, "req1 should have been evicted"
    end
  end
end
