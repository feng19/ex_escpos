defmodule ExEscpos.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_escpos,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:iconv, "~> 1.0"},
      {:qr_code, "~> 3.1", optional: true},
      {:bmp, "~> 0.1", only: :test}
    ]
  end
end
