defmodule ExLisp.MixProject do
  use Mix.Project

  def project do
    [
      app: :exlisp,
      version: "0.1.0",
      elixir: "~> 1.18",
      description: "A Lisp implementation and REPL running on Elixir/BEAM",
      package: package(),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      escript: escript(),
      deps: deps()
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nakagami/exlisp"
      }
    ]
  end

  defp escript do
    [
      main_module: ExLisp.CLI,
      emu_args: "-kernel shell_history enabled"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :iex, :ssl, :inets]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
