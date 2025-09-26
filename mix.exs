defmodule DdTraceEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :dd_trace_ex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {DDTrace, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finch, "~> 0.20"},
      {:ex_doc, "~> 0.34", only: :dev},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.0", only: :dev}
    ]
  end

  defp docs do
    [
      main: "Datadog"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
