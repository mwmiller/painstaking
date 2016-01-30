defmodule PainStaking.Mixfile do
  use Mix.Project

  def project do
    [app: :painstaking,
     version: "0.4.8",
     elixir: "~> 1.2",
     name: "PainStaking",
     source_url: "https://github.com/mwmiller/painstaking",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description,
     package: package,
     deps: deps]
  end

  def application do
    []
  end

  defp deps do
    [
      {:earmark, ">= 0.0.0", only: :dev},
      {:ex_doc, "~> 0.11.4", only: :dev},
      {:power_assert, "~> 0.0.8", only: :test},
      {:exoddic, "~> 1.0"},
    ]
  end

  defp description do
    """
    Bet stake sizing recommendations
    """
  end

  defp package do
    [
     files: ["lib", "mix.exs", "README*", "LICENSE*", ],
     maintainers: ["Matt Miller"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/mwmiller/painstaking",}
    ]
  end

end
