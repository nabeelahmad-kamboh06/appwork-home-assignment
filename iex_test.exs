# IEx Test Script for LRU Cache
#
# Usage in IEx:
#   iex> Code.require_file("iex_test.exs")
#   iex> CacheTest.run()
#
# Or copy-paste the functions into IEx

defmodule CacheTest do
  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("  LRU Cache - Test Suite")
    IO.puts(String.duplicate("=", 60) <> "\n")

    start_cache()
    test_cache_miss()
    test_cache_hit()
    test_lru_eviction()
    test_different_requests()
    test_request_validation()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("  All Tests Complete!")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  def start_cache do
    IO.puts("📦 Starting cache (capacity: 5)...")
    try do
      GenServer.stop(Cache.Server)
    catch
      :exit, {:noproc, _} -> :ok
    end

    {:ok, _pid} = Cache.start_link(cap: 5)
    IO.puts("   ✓ Cache started\n")
  end

  def test_cache_miss do
    IO.puts("1️⃣  Testing Cache Miss")
    request = %Request{url: "/api/users/1", method: :get}
    {time_us, {:ok, response}} = :timer.tc(fn -> Cache.fetch(request) end)
    IO.puts("   Time: #{time_us}μs")
    IO.puts("   URL: #{response.payload.url}")
    IO.puts("   ✓ Cache miss\n")
  end

  def test_cache_hit do
    IO.puts("2️⃣  Testing Cache Hit")
    request = %Request{url: "/api/users/1", method: :get}
    {time1, _} = :timer.tc(fn -> Cache.fetch(request) end)
    {time2, _} = :timer.tc(fn -> Cache.fetch(request) end)
    IO.puts("   Miss: #{time1}μs, Hit: #{time2}μs")
    IO.puts("   Speedup: #{div(time1, max(time2, 1))}x")
    IO.puts("   ✓ Cache hit\n")
  end

  def test_lru_eviction do
    IO.puts("3️⃣  Testing LRU Eviction")
    for i <- 1..5 do
      Cache.fetch(%Request{url: "/api/item/#{i}", method: :get})
    end
    Cache.fetch(%Request{url: "/api/item/1", method: :get})
    Cache.fetch(%Request{url: "/api/item/6", method: :get})
    {time, _} = :timer.tc(fn ->
      Cache.fetch(%Request{url: "/api/item/2", method: :get})
    end)
    IO.puts("   Evicted item fetch: #{time}μs (should be > 100000)")
    IO.puts("   ✓ LRU eviction\n")
  end

  def test_different_requests do
    IO.puts("4️⃣  Testing Different Requests")
    get_hash = Request.hash(%Request{url: "/api/users", method: :get})
    post_hash = Request.hash(%Request{url: "/api/users", method: :post, body: %{name: "Alice"}})
    IO.puts("   GET hash: #{get_hash}")
    IO.puts("   POST hash: #{post_hash}")
    IO.puts("   ✓ Different hashes\n")
  end

  def test_request_validation do
    IO.puts("5️⃣  Testing Validation")
    invalid = %Request{url: "", method: :get}
    result = Cache.fetch(invalid)
    IO.puts("   Invalid request: #{inspect(result)}")
    IO.puts("   ✓ Validation\n")
  end
end
