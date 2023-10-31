defmodule EtsLock.MixProject do
  use Mix.Project

  def project do
    [
      app: :ets_lock,
      version: "0.2.1",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A lock handler for ETS data",
      source_url: "https://github.com/appcues/ets_lock",
      homepage_url: "http://hexdocs.pm/ets_lock",
      package: [
        maintainers: ["Pete Gamache <pete@appcues.com>"],
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/appcues/ets_lock"
        }
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EtsLock.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.11", only: :test},
      {:ex_doc, "~> 0.21", only: :dev}
    ]
  end
end
