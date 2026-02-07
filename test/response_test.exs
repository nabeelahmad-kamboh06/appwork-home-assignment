defmodule ResponseTest do
  use ExUnit.Case, async: true

  describe "Response struct" do
    test "creates response with payload" do
      response = %Response{payload: "data"}
      assert response.payload == "data"
    end

    test "default TTL is 60 seconds" do
      response = %Response{payload: "data"}
      assert response.ttl == 60
    end

    test "custom TTL can be set" do
      response = %Response{payload: "data", ttl: 120}
      assert response.ttl == 120
    end

    test "metadata defaults to nil" do
      response = %Response{payload: "data"}
      assert response.metadata == nil
    end

    test "metadata can be set" do
      response = %Response{payload: "data", metadata: %{source: :test}}
      assert response.metadata == %{source: :test}
    end
  end

  describe "Response.ttl/1" do
    test "returns the TTL value" do
      response = %Response{payload: "data", ttl: 300}
      assert Response.ttl(response) == 300
    end
  end
end
