import Config

# Test-specific configuration
config :lru_cache,
  auto_start: false

# Reduce upstream latency for faster tests
config :lru_cache, Upstream,
  default_latency_ms: 100,
  default_ttl: 60

# Quieter logging in tests
config :logger, level: :warning
