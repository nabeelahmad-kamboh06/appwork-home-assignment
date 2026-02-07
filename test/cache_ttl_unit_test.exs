defmodule CacheTTLUnitTest do
  use ExUnit.Case, async: true

  describe "TTL Expiration Logic" do
    test "entry is not expired when within TTL" do
      inserted_at = System.system_time(:second)
      ttl = 60
      now = inserted_at + 30

      entry = %{
        response: %Response{payload: "test"},
        inserted_at: inserted_at,
        ttl: ttl
      }

      expired = now - entry.inserted_at > entry.ttl
      refute expired, "Entry should not be expired when now - inserted_at <= ttl"
    end

    test "entry is expired when past TTL" do
      inserted_at = System.system_time(:second)
      ttl = 60
      now = inserted_at + 61

      entry = %{
        response: %Response{payload: "test"},
        inserted_at: inserted_at,
        ttl: ttl
      }

      expired = now - entry.inserted_at > entry.ttl
      assert expired, "Entry should be expired when now - inserted_at > ttl"
    end

    test "entry is not expired exactly at TTL boundary" do
      inserted_at = System.system_time(:second)
      ttl = 60
      now = inserted_at + 60

      entry = %{
        response: %Response{payload: "test"},
        inserted_at: inserted_at,
        ttl: ttl
      }

      expired = now - entry.inserted_at > entry.ttl
      refute expired, "Entry should not be expired at exact TTL boundary"
    end

    test "entry with zero TTL expires immediately" do
      inserted_at = System.system_time(:second)
      ttl = 0
      now = inserted_at + 1

      entry = %{
        response: %Response{payload: "test", ttl: 0},
        inserted_at: inserted_at,
        ttl: ttl
      }

      expired = now - entry.inserted_at > entry.ttl
      assert expired, "Entry with TTL=0 should expire after any time passes"
    end
  end

  describe "TTL Entry Structure" do
    test "entry stores correct TTL from response" do
      response = %Response{payload: "test data", ttl: 120}

      entry = %{
        response: response,
        inserted_at: System.system_time(:second),
        ttl: Response.ttl(response)
      }

      assert entry.ttl == 120
      assert entry.response.payload == "test data"
    end
  end
end
