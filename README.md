# LRU + TTL Cache

A production-ready Elixir LRU (Least Recently Used) cache with TTL (Time-To-Live) support, built using OTP GenServer.

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Architecture](#architecture)
4. [Request Flow](#request-flow)
5. [Implementation Approach](#implementation-approach)
6. [Quick Start & Usage](#quick-start--usage)
7. [Telemetry & Observability](#telemetry--observability)
8. [Configuration](#configuration)
9. [Time Complexity Analysis](#time-complexity-analysis)
10. [Benefits](#benefits)
11. [Testing](#testing)
12. [V4 Future Implementation Guide](#v4-future-implementation-guide)
13. [Further Improvements](#further-improvements)
14. [Design Decisions](#design-decisions)

## Overview

This LRU Cache is designed for caching HTTP-like requests with automatic eviction and expiration. It provides:

- **Thread-safe operations** via OTP GenServer
- **LRU eviction** when capacity is exceeded
- **TTL-based expiration** with lazy evaluation
- **Full observability** via Telemetry integration
- **Production-ready** error handling and supervision

### Use Cases

- API response caching
- Database query caching
- Session data caching
- Expensive computation memoization

## Features

| Feature | Description |
|---------|-------------|
| **LRU Eviction** | Automatically evicts least recently used entries when capacity is exceeded |
| **TTL Support** | Lazy expiration checked on read - expired entries trigger upstream fetch |
| **Thread-Safe** | All operations serialized via GenServer - no race conditions |
| **Configurable** | Capacity, TTL, and server name customizable |
| **Telemetry** | Full observability with 6 telemetry events |
| **Production-Ready** | Error handling, validation, logging, supervision support |
| **Multiple Instances** | Run multiple named caches independently |

## Architecture

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT APPLICATION                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                             Cache (Public API)                              │
│  ┌─────────────┐  ┌─────────────────────┐                                   │
│  │   fetch/2   │  │  Request Validation │                                   │
│  └─────────────┘  └─────────────────────┘                                   │
└─────────────────────────────────────────────────────────────────────────────┘
           │                      │                      │
           │                      │                      │
           ▼                      ▼                      ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│   Request        │    │   Response       │    │  Cache.Behaviour │
│  ┌────────────┐  │    │  ┌────────────┐  │    │  (Interface)     │
│  │ validate/1 │  │    │  │   ttl/1    │  │    └──────────────────┘
│  │ hash/1     │  │    │  └────────────┘  │
│  └────────────┘  │    └──────────────────┘
└──────────────────┘
           │
           │ GenServer.call
           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Cache.Server (GenServer)                           │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                              STATE                                    │  │
│  │  ┌─────────────────────────────┐  ┌─────────────────────────────────┐ │  │
│  │  │         Store (Map)         │  │         LRU List                │ │  │
│  │  │   hash => {response,        │  │   [most_recent, ..., oldest]    │ │  │
│  │  │            inserted_at,     │  │                                 │ │  │
│  │  │            ttl}             │  │   O(1) prepend                  │ │  │
│  │  │                             │  │   O(n) move-to-front            │ │  │
│  │  │   O(1) lookup/insert        │  │                                 │ │  │
│  │  └─────────────────────────────┘  └─────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Emits Telemetry Events:                                                    │
│    • [:cache, :fetch, :start/:stop/:hit/:miss/:expired]                     │
│    • [:cache, :evict]                                                       │
└─────────────────────────────────────────────────────────────────────────────┘
           │                                                    │
           │ Cache Miss / TTL Expired                           │ Telemetry Events
           ▼                                                    ▼
┌───────────────────────┐                        ┌─────────────────────────────┐
│       Upstream        │                        │      Cache.Telemetry        │
│  ┌─────────────────┐  │                        │  ┌────────────────────────┐ │
│  │   fetch/1       │  │                        │  │ Event Handlers         │ │
│  │                 │  │                        │  │                        │ │
│  │ External API    │  │                        │  │ → Logging              │ │
│  │ with latency    │  │                        │  │ → Metrics              │ │
│  └─────────────────┘  │                        │  │ → Monitoring           │ │
│                       │                        │  │ → Alerting             │ │
│  Returns: Response    │                        │  └────────────────────────┘ │
└───────────────────────┘                        └─────────────────────────────┘
```

### Module Structure

```
lib/
├── application.ex          # OTP Application (supervision)
├── cache/
│   ├── behaviour.ex        # Interface contract (@callback)
│   ├── cache.ex            # Public API with validation
│   ├── server.ex           # Core GenServer (LRU + TTL logic)
│   └── telemetry.ex        # Observability handlers
├── request.ex              # Request struct with hash/validate
├── response.ex             # Response struct with TTL
└── upstream.ex             # External service simulation
```

### Data Structures

```elixir
# GenServer State
%{
  cap: 1000,                          # Maximum entries
  store: %{                           # Hash → Entry mapping (O(1) lookup)
    123456 => %{
      response: %Response{...},
      inserted_at: 1706745600,        # Unix timestamp (seconds)
      ttl: 60                         # Seconds
    }
  },
  lru: [123456, 789012, ...]          # Most recent first
}

# Request Struct
%Request{
  url: "/api/users/1",                # Required
  method: :get,                       # Required
  headers: %{"auth" => "token"},      # Optional
  body: %{name: "Alice"}              # Optional
}

# Response Struct
%Response{
  payload: %{data: "..."},            # Required
  ttl: 60,                            # Default: 60 seconds
  metadata: %{source: :upstream}      # Optional
}
```

## Request Flow

```
Cache.fetch(request)
        │
        ▼
┌──────────────────────────┐
│ 📊 Emit Telemetry:       │
│    [:cache, :fetch,      │
│     :start]              │
└──────────────────────────┘
        │
        ▼
┌───────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  Validate Request │────▶│   Compute Hash   │────▶│   Lookup in Store   │
│  (Request module) │     │ (:erlang.phash2) │     │    (Map.get)        │
└───────────────────┘     └──────────────────┘     └─────────────────────┘
                                                             │
                          ┌──────────────────────────────────┴────────────────┐
                          │                                                   │
                          ▼                                                   ▼
                   ┌─────────────┐                                    ┌──────────────┐
                   │  CACHE HIT  │                                    │  CACHE MISS  │
                   └─────────────┘                                    └──────────────┘
                          │                                                   │
                          ▼                                                   ▼
                   ┌─────────────┐                                    ┌──────────────────────────┐
                   │ Check TTL   │                                    │ 📊 Emit Telemetry:       │
                   │ (expired?)  │                                    │    [:cache, :fetch,      │
                   └─────────────┘                                    │     :miss]               │
                          │                                           └──────────────────────────┘
             ┌────────────┴────────────┐                                        │
             │                         │                                        │
             ▼                         ▼                                        ▼
      ┌───────────┐            ┌───────────────┐                        ┌──────────────┐
      │  Valid    │            │   Expired     │                        │ Fetch from   │
      │  Entry    │            │   Entry       │                        │  Upstream    │
      └───────────┘            └───────────────┘                        └──────────────┘
             │                         │                                        │
             ▼                         ▼                                        │
      ┌──────────────────────────┐  ┌──────────────────────────┐                │
      │ 📊 Emit Telemetry:       │  │ 📊 Emit Telemetry:       │                 │
      │    [:cache, :fetch,      │  │    [:cache, :fetch,      │                │
      │     :hit]                │  │     :expired]            │                │
      └──────────────────────────┘  └──────────────────────────┘                │
             │                         │                                        │
             │                         ▼                                        │
             │                  ┌──────────────┐                                │
             │                  │ Remove       │                                │
             │                  │ Expired      │                                │
             │                  │ Entry        │                                │
             │                  └──────────────┘                                │
             │                         │                                        │
             ▼                         └────────────────────────────────────────┤
      ┌───────────┐                                                             │
      │ Touch LRU │                                                             │
      │ (move to  │                                                             │
      │  front)   │                                                             │
      └───────────┘                                                             │
             │                                                                  │
             │                                                                  ▼
             │                                                          ┌──────────────┐
             │                                                          │ Insert Entry │
             │                                                          │ into Store   │
             │                                                          └──────────────┘
             │                                                                  │
             │                                                                  ▼
             │                                                          ┌──────────────┐
             │                                                          │ Prepend to   │
             │                                                          │  LRU List    │
             │                                                          └──────────────┘
             │                                                                  │
             │                                                                  ▼
             │                                                          ┌──────────────┐
             │                                                          │ Evict LRU if │
             │                                                          │ over capacity│
             │                                                          └──────────────┘
             │                                                                  │
             │                                                                  ▼
             │                                                          ┌──────────────────────────┐
             │                                                          │ 📊 Emit Telemetry:       │
             │                                                          │    [:cache, :evict]      │
             │                                                          │    (if eviction occurs)  │
             │                                                          └──────────────────────────┘
             │                                                                  │
             └──────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
                              ┌──────────────────────────┐
                              │ 📊 Emit Telemetry:       │
                              │    [:cache, :fetch,      │
                              │     :stop]               │
                              │    (with duration)       │
                              └──────────────────────────┘
                                       │
                                       ▼
                              ┌─────────────┐
                              │   Return    │
                              │  Response   │
                              └─────────────┘
```

## Implementation Approach

### Core Design Principles

1. **Correctness over Performance**: GenServer serialization prevents race conditions
2. **Simplicity over Complexity**: O(n) list operations are acceptable for bounded n
3. **Lazy Evaluation**: TTL checked on read, not via background processes
4. **Separation of Concerns**: Public API, internal server, and telemetry are separate

### LRU Implementation

```elixir
# Move-to-front on access
defp touch_lru(state, hash) do
  new_lru = [hash | List.delete(state.lru, hash)]
  %{state | lru: new_lru}
end

# Example:
# Initial:   [C, B, A]  (C most recent, A least recent)
# Access B:  [B, C, A]  (B moved to front)
# Insert D:  [D, B, C, A]
# If cap=3:  [D, B, C]  (A evicted)
```

### TTL Implementation (Lazy Expiration)

```elixir
defp expired?(entry, now) do
  now - entry.inserted_at > entry.ttl
end

# On fetch:
# - If entry exists and NOT expired → return cached (cache hit)
# - If entry exists and IS expired → remove, fetch from upstream
# - If entry doesn't exist → fetch from upstream (cache miss)
```

### Hash Function

```elixir
def hash(%Request{} = request) do
  :erlang.phash2({
    request.url,
    request.method,
    normalize_headers(request.headers),  # Case-insensitive, sorted
    request.body
  })
end
```

## Quick Start & Usage

### Installation

Add to your `mix.exs`:

```elixir
def deps do
  [{:lru_cache, "~> 0.1.0"}]
end
```

### Basic Usage

```elixir
# Start the cache
{:ok, _pid} = Cache.start_link(cap: 1000)

# Create a request
request = %Request{url: "/api/users/1", method: :get}

# Fetch - first call goes to upstream (slow)
{:ok, response} = Cache.fetch(request)

# Subsequent calls return cached response (fast)
{:ok, cached} = Cache.fetch(request)

# Check cache stats
{:ok, stats} = Cache.stats()
# => %{size: 1, cap: 1000, utilization: 0.1, available: 999}
```

### Supervision Tree

```elixir
# In your application.ex or supervisor
children = [
  {Cache, cap: 1000}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### Multiple Named Caches

```elixir
# Start multiple independent caches
{:ok, _} = Cache.start_link(cap: 1000, name: :users_cache)
{:ok, _} = Cache.start_link(cap: 500, name: :products_cache)

# Use them independently
Cache.fetch(user_request, name: :users_cache)
Cache.fetch(product_request, name: :products_cache)
```

### IEx Commands for Testing

```elixir
# Start IEx
iex -S mix

# Start cache
{:ok, _} = Cache.start_link(cap: 5)

# Create requests
req1 = %Request{url: "/api/users/1", method: :get}
req2 = %Request{url: "/api/users/2", method: :get}

# Fetch (first call - slow, hits upstream)
{:ok, resp1} = Cache.fetch(req1)

# Fetch again (fast - cached)
{:ok, resp2} = Cache.fetch(req1)

# Check stats
Cache.stats()

# Enable telemetry logging
Cache.Telemetry.attach_default_handler(level: :info)

# Now fetch and see telemetry logs
Cache.fetch(req2)
```

## Telemetry & Observability

### Why Telemetry?

Telemetry provides **observability** - the ability to understand what your cache is doing in production without modifying code.

| Use Case | Telemetry Event | Benefit |
|----------|-----------------|---------|
| **Performance Monitoring** | `:hit` vs `:miss` | Calculate hit rate |
| **Latency Tracking** | `:stop` with duration | Identify slow operations |
| **Capacity Planning** | `:evict` | Detect when cache is too small |
| **TTL Tuning** | `:expired` | Identify TTL misconfigurations |
| **Production Debugging** | All events | Understand cache behavior |

### Telemetry Events

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:cache, :fetch, :start]` | `%{}` | `%{request: request}` |
| `[:cache, :fetch, :stop]` | `%{duration: native_time}` | `%{request: request}` |
| `[:cache, :fetch, :hit]` | `%{}` | `%{hash: integer}` |
| `[:cache, :fetch, :miss]` | `%{}` | `%{hash: integer}` |
| `[:cache, :fetch, :expired]` | `%{}` | `%{hash: integer}` |
| `[:cache, :evict]` | `%{}` | `%{hash: integer}` |

### Attaching Handlers

```elixir
# Use built-in logging handler
Cache.Telemetry.attach_default_handler(level: :info)

# Detach when done
Cache.Telemetry.detach_default_handler()
```

### Custom Handlers

```elixir
# Track cache hit rate for monitoring dashboard
:telemetry.attach(
  "cache-hit-metrics",
  [:cache, :fetch, :hit],
  fn _event, _measurements, metadata, _config ->
    StatsD.increment("cache.hit", tags: ["hash:#{metadata.hash}"])
  end,
  nil
)

# Track cache miss rate
:telemetry.attach(
  "cache-miss-metrics",
  [:cache, :fetch, :miss],
  fn _event, _measurements, _metadata, _config ->
    StatsD.increment("cache.miss")
  end,
  nil
)

# Alert on high eviction rate
:telemetry.attach(
  "cache-eviction-alert",
  [:cache, :evict],
  fn _event, _measurements, _metadata, _config ->
    # Track eviction count, alert if threshold exceeded
    Alerting.increment_and_check(:cache_evictions)
  end,
  nil
)

# Track latency histogram
:telemetry.attach(
  "cache-latency",
  [:cache, :fetch, :stop],
  fn _event, %{duration: duration}, _metadata, _config ->
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    Prometheus.Histogram.observe(:cache_fetch_duration, duration_ms)
  end,
  nil
)
```

### Telemetry Module API

```elixir
# Get list of all events
Cache.Telemetry.events()
# => [[:cache, :fetch, :start], [:cache, :fetch, :stop], ...]

# Attach default logging handler
Cache.Telemetry.attach_default_handler(level: :debug)

# Detach default handler
Cache.Telemetry.detach_default_handler()
```

## API Reference

### Cache.start_link/1

Starts the cache server.

```elixir
{:ok, pid} = Cache.start_link(cap: 500, name: :my_cache)
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:cap` | `pos_integer` | 100 | Maximum cache entries |
| `:name` | `atom` | `Cache.Server` | Process registration name |

### Cache.fetch/2

Fetches a response, returning cached data or calling upstream.

```elixir
{:ok, response} = Cache.fetch(request)
{:ok, response} = Cache.fetch(request, name: :my_cache, timeout: 5000)
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:name` | `atom` | `Cache.Server` | Target cache server |
| `:timeout` | `pos_integer` | 5000 | GenServer call timeout (ms) |

**Returns:**
- `{:ok, Response.t()}` - On success
- `{:error, :cache_not_running}` - Cache not started
- `{:error, :timeout}` - Request timed out
- `{:error, {:invalid_request, reason}}` - Invalid request

### Cache.stats/1

Returns cache statistics.

```elixir
{:ok, stats} = Cache.stats()
# => %{size: 42, cap: 1000, utilization: 4.2, available: 958}
```

### Request.hash/1

Computes deterministic hash for cache key.

```elixir
hash = Request.hash(%Request{url: "/api/users", method: :get})
# => 123456789
```

### Request.validate/1

Validates a request struct.

```elixir
:ok = Request.validate(%Request{url: "/api/users", method: :get})
{:error, "url must be a non-empty string"} = Request.validate(%Request{url: "", method: :get})
```

### Response.ttl/1

Returns TTL in seconds.

```elixir
ttl = Response.ttl(%Response{payload: %{}, ttl: 120})
# => 120
```

## Configuration

### Application Config

```elixir
# config/config.exs
config :lru_cache,
  auto_start: false,    # Auto-start cache on app boot
  cap: 100              # Default capacity

config :lru_cache, Upstream,
  default_latency_ms: 100,  # Simulated latency
  default_ttl: 60           # Default TTL in seconds
```

### Environment-Specific Config

```elixir
# config/dev.exs
config :lru_cache,
  auto_start: false

# config/prod.exs
config :lru_cache,
  auto_start: true,
  cap: 10_000

# config/test.exs
config :lru_cache,
  auto_start: false

config :lru_cache, Upstream,
  default_latency_ms: 100,
  default_ttl: 20
```

### Runtime Config (12-Factor)

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :lru_cache,
    cap: String.to_integer(System.get_env("CACHE_CAPACITY", "10000"))
end
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CACHE_CAPACITY` | Override cache capacity | 10000 |
| `CACHE_TTL` | Override default TTL | 60 |


## Time Complexity Analysis

### Operation Complexity

| Operation | Time Complexity | Notes |
|-----------|-----------------|-------|
| **Lookup** | O(1) | Map.get on store |
| **Insert** | O(n) | List.delete + prepend |
| **Touch LRU** | O(n) | List.delete + prepend |
| **Capacity Check** | O(1) | map_size (optimized) |
| **Evict** | O(n) | List.last + List.delete |
| **Hash Computation** | O(k) | k = request size |

### Why O(n) is Acceptable

1. **n is bounded**: `cap` limits list size (typically 100-10,000)
2. **List operations are fast**: BEAM linked lists are optimized
3. **Hit path is fast**: Most operations are hits (lookup + prepend)
4. **Network latency dominates**: Upstream calls are ~1-100ms; O(n) is ~1-50μs

### Benchmark Reality

```
n = 1,000:   List operations ≈ 1-5μs
n = 10,000:  List operations ≈ 10-50μs
n = 100,000: List operations ≈ 100-500μs (consider V4)
```

### Performance Characteristics

| Metric | Value |
|--------|-------|
| **Throughput** | ~50,000 cache hits/second (single GenServer) |
| **Latency (hit)** | ~1-10μs |
| **Latency (miss)** | Upstream latency + ~1ms overhead |
| **Memory per entry** | ~200 bytes + response payload size |


## Benefits

### Technical Benefits

| Benefit | Description |
|---------|-------------|
| **Thread-Safe** | GenServer serialization prevents race conditions |
| **Correct LRU** | True LRU with move-to-front on access |
| **Lazy TTL** | No background processes, simpler system |
| **Observable** | Full telemetry integration |
| **Supervised** | OTP supervision for fault tolerance |
| **Configurable** | Multiple config layers for flexibility |

### Operational Benefits

| Benefit | Description |
|---------|-------------|
| **Zero-Code Observability** | Attach handlers without code changes |
| **Runtime Config** | Environment variables for production |
| **Multiple Caches** | Run independent named instances |
| **Graceful Degradation** | Returns error tuples, doesn't crash |

### Developer Benefits

| Benefit | Description |
|---------|-------------|
| **Simple API** | Just `Cache.fetch(request)` |
| **Well-Tested** | 64 tests covering all scenarios |
| **Well-Documented** | Comprehensive @moduledoc and @doc |
| **Type Specs** | Full @spec coverage for Dialyzer |


## Testing

### Running Tests

```bash
# Run all tests
mix test

# Run with trace (verbose output)
mix test --trace

# Run specific test file
mix test test/cache_v2_test.exs

# Run with coverage
mix test --cover
```

### Test Structure

```
test/
├── request_test.exs              # Unit: Request struct, hash, validation
├── response_test.exs             # Unit: Response struct, TTL
├── upstream_test.exs             # Unit: Upstream service simulation
├── cache_v1_test.exs             # Integration: Basic caching
├── cache_v2_test.exs             # Integration: LRU eviction
├── cache_v3_test.exs             # Integration: TTL expiration
├── cache_ttl_unit_test.exs       # Unit: TTL logic
├── cache_ttl_expiration_test.exs # Integration: TTL scenarios
├── cache_production_test.exs     # Production: Edge cases, errors
└── test_helper.exs               # Test configuration
```

### Test Coverage

- **64 tests total**
- Unit tests for Request, Response, Upstream
- Integration tests for cache behavior (V1, V2, V3)
- Edge case tests (unicode, special chars, large payloads)
- Error handling tests
- TTL expiration tests


## V4 Future Implementation Guide

### V4 Goals

1. **ETS for Storage**: O(1) concurrent reads
2. **O(1) LRU Updates**: Doubly-linked list in ETS
3. **Reduced GenServer Contention**: Direct ETS lookup for hits
4. **Sharding**: Horizontal scalability

### V4 Implementation Steps

#### Step 1: Add ETS Table

```elixir
defmodule Cache.V4.Server do
  use GenServer

  def init(opts) do
    cap = Keyword.get(opts, :cap, 1000)
    
    # Create ETS table for O(1) concurrent reads
    table = :ets.new(:cache_store, [
      :set,
      :public,  # Allow direct reads from other processes
      read_concurrency: true
    ])
    
    # Create ETS table for doubly-linked list (LRU)
    lru_table = :ets.new(:cache_lru, [:ordered_set, :public])
    
    {:ok, %{table: table, lru_table: lru_table, cap: cap, size: 0}}
  end
end
```

#### Step 2: Implement Doubly-Linked List in ETS

```elixir
# LRU entry: {hash, prev_hash, next_hash, timestamp}
defp touch_lru_ets(state, hash) do
  now = System.monotonic_time()
  
  # Remove from current position
  case :ets.lookup(state.lru_table, hash) do
    [{^hash, prev, next, _ts}] ->
      # Update neighbors
      if prev, do: :ets.update_element(state.lru_table, prev, {3, next})
      if next, do: :ets.update_element(state.lru_table, next, {2, prev})
    [] ->
      :ok
  end
  
  # Insert at head
  old_head = state.head
  :ets.insert(state.lru_table, {hash, nil, old_head, now})
  if old_head, do: :ets.update_element(state.lru_table, old_head, {2, hash})
  
  %{state | head: hash}
end
```

#### Step 3: Implement Sharding

```elixir
defmodule Cache.V4.Router do
  @shard_count 16
  
  def get_shard(request) do
    hash = Request.hash(request)
    shard_id = rem(hash, @shard_count)
    :"cache_shard_#{shard_id}"
  end
  
  def fetch(request) do
    shard = get_shard(request)
    Cache.V4.Server.fetch(shard, request)
  end
end
```

#### Step 4: Implement Read Path Bypass

```elixir
def fetch(request) do
  hash = Request.hash(request)
  shard = get_shard(request)
  
  # Try direct ETS lookup first (no GenServer call)
  case :ets.lookup(shard.table, hash) do
    [{^hash, entry}] when not expired?(entry) ->
      # Async LRU update (non-blocking)
      GenServer.cast(shard.pid, {:touch_lru, hash})
      {:ok, entry.response}
    
    _ ->
      # Fall back to GenServer for miss/expired
      GenServer.call(shard.pid, {:fetch, request})
  end
end
```

### V4 Complexity Comparison

| Operation | V3 | V4 Target |
|-----------|-----|-----------|
| Lookup | O(1) | O(1) |
| LRU Touch | O(n) | O(1) |
| Evict | O(n) | O(1) |
| Throughput | 50k ops/sec | 500k+ ops/sec |

### When to Implement V4

- Profiling shows GenServer is bottleneck
- Hit rate > 99% and latency matters
- Cache size > 100,000 entries
- Need > 100,000 ops/sec
- Multiple processes need concurrent reads

## Further Improvements

#### 1. Add Background Cleanup (Optional)
#### 2. Add Cache Warmup
#### 3. Add Cache Invalidation
#### 4. Add Bulk Operations
#### 5. Add Compression for Large Payloads

### Production Alternatives

For production-scale caching, consider:

| Library | Use Case |
|---------|----------|
| **Cachex** | Full-featured Elixir cache with TTL, limits, warmup |
| **ConCache** | ETS-based with TTL and callbacks |
| **Nebulex** | Distributed cache with adapters (Redis, Memcached) |
| **Redis** | External distributed caching |

## Design Decisions

### Why GenServer?

- **Thread-safe**: Serialized access prevents race conditions
- **OTP Standard**: Familiar patterns, supervision support
- **Simple State**: Easy to reason about and debug

### Why Lazy TTL?

- **No background processes**: Simpler, fewer failure modes
- **Redis approach**: Industry-standard pattern
- **Memory efficiency**: LRU eviction handles cleanup

### Why List-Based LRU?

- **Clear and verifiable**: Easy to understand and test
- **O(n) acceptable**: n is bounded by capacity
- **Pure Elixir**: No external dependencies

### Why Result Tuples?

- **Explicit errors**: Caller must handle both cases
- **Elixir convention**: Standard pattern
- **Composable**: Works with `with` and pipes

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass (`mix test`)
5. Run Credo (`mix credo --strict`)
6. Submit a pull request
