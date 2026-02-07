defmodule RequestTest do
  use ExUnit.Case, async: true

  describe "Request struct" do
    test "creates request with required fields" do
      request = %Request{url: "/api/users", method: :get}
      assert request.url == "/api/users"
      assert request.method == :get
    end

    test "optional fields default to nil" do
      request = %Request{url: "/api/users", method: :get}
      assert request.headers == nil
      assert request.body == nil
    end
  end

  describe "Request.hash/1" do
    test "returns an integer" do
      request = %Request{url: "/api/users", method: :get}
      assert is_integer(Request.hash(request))
    end

    test "same request returns same hash" do
      request1 = %Request{url: "/api/users", method: :get}
      request2 = %Request{url: "/api/users", method: :get}
      assert Request.hash(request1) == Request.hash(request2)
    end

    test "different requests return different hashes" do
      request1 = %Request{url: "/api/users", method: :get}
      request2 = %Request{url: "/api/posts", method: :get}
      assert Request.hash(request1) != Request.hash(request2)
    end

    test "different methods produce different hashes" do
      request1 = %Request{url: "/api/users", method: :get}
      request2 = %Request{url: "/api/users", method: :post}
      assert Request.hash(request1) != Request.hash(request2)
    end

    test "different headers produce different hashes" do
      request1 = %Request{url: "/api/users", method: :get, headers: %{"auth" => "token1"}}
      request2 = %Request{url: "/api/users", method: :get, headers: %{"auth" => "token2"}}
      assert Request.hash(request1) != Request.hash(request2)
    end

    test "different bodies produce different hashes" do
      request1 = %Request{url: "/api/users", method: :post, body: %{name: "Alice"}}
      request2 = %Request{url: "/api/users", method: :post, body: %{name: "Bob"}}
      assert Request.hash(request1) != Request.hash(request2)
    end

    test "header order does not affect hash" do
      # Headers are normalized and sorted
      request1 = %Request{url: "/api/users", method: :get, headers: %{"a" => "1", "b" => "2"}}
      request2 = %Request{url: "/api/users", method: :get, headers: %{"b" => "2", "a" => "1"}}
      assert Request.hash(request1) == Request.hash(request2)
    end

    test "header case is normalized" do
      request1 = %Request{url: "/api/users", method: :get, headers: %{"Content-Type" => "json"}}
      request2 = %Request{url: "/api/users", method: :get, headers: %{"content-type" => "json"}}
      assert Request.hash(request1) == Request.hash(request2)
    end
  end

  describe "Request.validate/1" do
    test "valid request returns :ok" do
      request = %Request{url: "/api/users", method: :get}
      assert Request.validate(request) == :ok
    end

    test "empty url returns error" do
      request = %Request{url: "", method: :get}
      assert {:error, message} = Request.validate(request)
      assert message =~ "url"
    end

    test "invalid method returns error" do
      request = %Request{url: "/api/users", method: :invalid}
      assert {:error, message} = Request.validate(request)
      assert message =~ "method"
    end

    test "all valid HTTP methods are accepted" do
      for method <- [:get, :post, :put, :patch, :delete, :head, :options] do
        request = %Request{url: "/api/users", method: method}
        assert Request.validate(request) == :ok
      end
    end
  end
end
