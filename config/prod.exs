import Config

# Production configuration
config :lru_cache,
  auto_start: true,
  cap: 10_000

config :lru_cache, Upstream,
  default_latency_ms: 0,  # No simulated latency in production
  default_ttl: 300        # 5 minutes default TTL

config :logger, level: :info
