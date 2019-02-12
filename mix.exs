defmodule Trekmap.MixProject do
  use Mix.Project

  def project do
    [
      app: :trekmap,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Trekmap.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:hackney, "~> 1.15"},
      {:uuid, "~> 1.1"},
      {:jason, "~> 1.1"},
      {:protobuf, "~> 0.5.4"},
      {:google_protos, "~> 0.1"},
      {:nimble_csv, "~> 0.5.0"}
    ]
  end
end
