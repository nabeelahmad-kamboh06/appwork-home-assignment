defmodule UpstreamTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  describe "Upstream.fetch/2" do
    test "returns ok tuple with Response struct" do
      request = %Request{url: "/api/test", method: :get}
      assert {:ok, response} = Upstream.fetch(request, latency_ms: 0)

      assert %Response{} = response
      assert response.payload.url == "/api/test"
      assert response.payload.method == :get
    end

    test "simulates latency" do
      request = %Request{url: "/api/test", method: :get}

      {elapsed_us, {:ok, _response}} =
        :timer.tc(fn -> Upstream.fetch(request, latency_ms: 50) end)

      # Should take at least 50ms (50_000 microseconds)
      assert elapsed_us >= 50_000
    end

    test "respects custom TTL" do
      request = %Request{url: "/api/test", method: :get}
      {:ok, response} = Upstream.fetch(request, latency_ms: 0, ttl: 120)

      assert response.ttl == 120
    end

    test "includes metadata with source" do
      request = %Request{url: "/api/test", method: :get}
      {:ok, response} = Upstream.fetch(request, latency_ms: 0)

      assert response.metadata == %{source: :upstream}
    end

    test "includes fetched_at timestamp in payload" do
      request = %Request{url: "/api/test", method: :get}
      {:ok, response} = Upstream.fetch(request, latency_ms: 0)

      assert %DateTime{} = response.payload.fetched_at
    end

    test "can simulate error" do
      request = %Request{url: "/api/test", method: :get}

      capture_log(fn ->
        assert {:error, :simulated_error} = Upstream.fetch(request, simulate_error: true, latency_ms: 0)
      end)
    end
  end
end
