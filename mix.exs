defmodule PainStaking.Mixfile do
  use Mix.Project

  def project do
    [
      app: :painstaking,
      version: "1.0.3",
      elixir: "~> 1.7",
      name: "PainStaking",
      source_url: "https://github.com/mwmiller/painstaking",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:ex_doc, "~> 0.23", only: :dev},
      {:exoddic, "~> 1.3"},
    ]
  end

  defp description do
    """
    Bet stake sizing recommendations
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Matt Miller"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/mwmiller/painstaking"}
    ]
  end
end
