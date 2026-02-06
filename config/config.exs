# General application configuration
import Config

# Cache configuration
config :lru_cache,
  # Set to true to auto-start the cache on application boot
  auto_start: false,
  # Default cache capacity
  cap: 100

# Upstream service configuration
config :lru_cache, Upstream,
  default_latency_ms: 1000,
  default_ttl: 20

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
