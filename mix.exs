defmodule ReverseProxyPlugWebsocket.MixProject do
  use Mix.Project

  def project do
    [
      app: :reverse_proxy_plug_websocket,
      description: "Support reverse proxying of websocket connections natively in Elixir",
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.14"},
      {:gun, "~> 2.0", optional: true},
      {:websockex, "~> 0.4.3", optional: true},
      {:websock_adapter, "~> 0.5"},
      {:websock, "~> 0.5"},
      {:ex_doc, "~> 0.30.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/mwhitworth/reverse_proxy_plug_websocket"}
    ]
  end
end
