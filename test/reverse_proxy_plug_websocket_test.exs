defmodule ReverseProxyPlugWebsocketTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias ReverseProxyPlugWebsocket

  describe "init/1" do
    test "initializes with valid configuration" do
      opts = [upstream_uri: "ws://localhost:4000/socket", path: "/socket"]
      config = ReverseProxyPlugWebsocket.init(opts)

      assert config.upstream_uri == "ws://localhost:4000/socket"
      assert config.path == "/socket"
      assert config.adapter == ReverseProxyPlugWebsocket.Adapters.Gun
    end

    test "raises on missing upstream_uri" do
      assert_raise ArgumentError, ~r/Invalid configuration/, fn ->
        ReverseProxyPlugWebsocket.init(path: "/socket")
      end
    end

    test "raises on missing path" do
      assert_raise ArgumentError, ~r/Invalid configuration/, fn ->
        ReverseProxyPlugWebsocket.init(upstream_uri: "ws://localhost:4000/socket")
      end
    end

    test "normalizes path to start with /" do
      opts = [upstream_uri: "ws://localhost:4000/socket", path: "socket"]
      config = ReverseProxyPlugWebsocket.init(opts)

      assert config.path == "/socket"
    end
  end

  describe "call/2" do
    setup do
      config =
        ReverseProxyPlugWebsocket.init(
          upstream_uri: "ws://localhost:4000/socket",
          path: "/socket"
        )

      {:ok, config: config}
    end

    test "passes through non-WebSocket requests", %{config: config} do
      conn =
        conn(:get, "/")
        |> ReverseProxyPlugWebsocket.call(config)

      refute conn.halted
    end

    test "passes through requests to different paths", %{config: config} do
      conn =
        conn(:get, "/other")
        |> Map.put(:host, "localhost")
        |> put_req_header("connection", "Upgrade")
        |> put_req_header("upgrade", "websocket")
        |> put_req_header("sec-websocket-version", "13")
        |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
        |> ReverseProxyPlugWebsocket.call(config)

      refute conn.halted
    end

    test "detects WebSocket upgrade requests on matching path", %{config: config} do
      conn =
        conn(:get, "http://localhost/socket")
        |> Map.put(:host, "localhost")
        |> put_req_header("connection", "Upgrade")
        |> put_req_header("upgrade", "websocket")
        |> put_req_header("sec-websocket-version", "13")
        |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")

      # Note: This will fail in tests without a proper WebSocket server
      # In real usage with Cowboy/Bandit, this would upgrade successfully
      assert_raise WebSockAdapter.UpgradeError, fn ->
        ReverseProxyPlugWebsocket.call(conn, config)
      end
    end

    test "detects WebSocket upgrade with mixed-case headers", %{config: config} do
      conn =
        conn(:get, "http://localhost/socket")
        |> Map.put(:host, "localhost")
        |> put_req_header("connection", "keep-alive, Upgrade")
        |> put_req_header("upgrade", "WebSocket")
        |> put_req_header("sec-websocket-version", "13")
        |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")

      assert_raise WebSockAdapter.UpgradeError, fn ->
        ReverseProxyPlugWebsocket.call(conn, config)
      end
    end

    test "proxies subpaths under configured path", %{config: config} do
      conn =
        conn(:get, "http://localhost/socket/channel")
        |> Map.put(:host, "localhost")
        |> put_req_header("connection", "Upgrade")
        |> put_req_header("upgrade", "websocket")
        |> put_req_header("sec-websocket-version", "13")
        |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")

      assert_raise WebSockAdapter.UpgradeError, fn ->
        ReverseProxyPlugWebsocket.call(conn, config)
      end
    end
  end
end
