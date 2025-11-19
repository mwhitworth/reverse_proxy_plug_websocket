defmodule Examples.BasicUsage do
  @moduledoc """
  Basic example of using ReverseProxyPlugWebsocket in a Plug application.

  ## Setup

  Add to your mix.exs:
      def deps do
        [
          {:reverse_proxy_plug_websocket, "~> 0.1.0"},
          {:plug_cowboy, "~> 2.0"}
        ]
      end

  ## Running

      mix run --no-halt examples/basic_usage.ex

  Then connect with a WebSocket client to ws://localhost:4001/socket
  """

  use Plug.Router

  # Proxy WebSocket connections to an upstream server
  # Must come BEFORE :match and :dispatch
  plug ReverseProxyPlugWebsocket,
    upstream_uri: "wss://echo.websocket.org/",
    path: "/socket"

  plug :match
  plug :dispatch

  match _ do
    send_resp(conn, 200, "WebSocket proxy running on ws://localhost:4001/socket")
  end
end

# To run this example:
# 1. Start an upstream WebSocket server on ws://localhost:4000/socket
# 2. Run: mix run --no-halt examples/basic_usage.ex
# 3. Connect a WebSocket client to ws://localhost:4001/socket
