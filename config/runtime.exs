import Config

# Runtime configuration
# This file is executed at runtime, allowing environment variable configuration

if config_env() == :prod do
  # Override cache capacity from environment variable
  if cap = System.get_env("CACHE_CAPACITY") do
    config :lru_cache, cap: String.to_integer(cap)
  end

  # Override TTL from environment variable
  if ttl = System.get_env("CACHE_TTL") do
    config :lru_cache, Upstream, default_ttl: String.to_integer(ttl)
  end
end
