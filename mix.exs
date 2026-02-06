defmodule LruCache.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/example/lru_cache"

  def project do
    [
      app: :lru_cache,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Documentation
      name: "LRU Cache",
      description: "A production-ready LRU + TTL cache using OTP GenServer",
      source_url: @source_url,
      docs: docs(),

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {LruCache.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Optional: Telemetry for observability
      {:telemetry, "~> 1.0", optional: true},

      # Dev/Test dependencies
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
