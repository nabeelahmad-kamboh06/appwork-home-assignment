defmodule LruCache.Application do
  @moduledoc """
  Application module for the LRU Cache.

  Starts the cache server under supervision when the application starts.
  Configure via application environment:

      config :lru_cache,
        auto_start: true,
        cap: 1000

  Set `auto_start: false` to prevent automatic startup (e.g., in tests).
  """

  use Application

  require Logger

  @impl Application
  def start(_type, _args) do
    children = build_children()

    opts = [strategy: :one_for_one, name: LruCache.Supervisor]

    Logger.info("Starting LRU Cache application")
    Supervisor.start_link(children, opts)
  end

  defp build_children do
    if Application.get_env(:lru_cache, :auto_start, false) do
      cap = Application.get_env(:lru_cache, :cap, 100)
      [{Cache, cap: cap}]
    else
      []
    end
  end
end
