defmodule ReverseProxyPlugWebsocket.ConfigTest do
  use ExUnit.Case, async: true

  alias ReverseProxyPlugWebsocket.Config

  describe "validate/1" do
    test "validates a minimal valid configuration" do
      opts = [upstream_uri: "ws://localhost:4000/socket", path: "/socket"]

      assert {:ok, config} = Config.validate(opts)
      assert config.upstream_uri == "ws://localhost:4000/socket"
      assert config.path == "/socket"
      assert config.adapter == ReverseProxyPlugWebsocket.Adapters.Gun
      assert config.headers == []
      assert config.connect_timeout == 5000
      assert config.upgrade_timeout == 5000
      assert config.protocols == []
      assert config.tls_opts == []
    end

    test "validates a full configuration" do
      opts = [
        upstream_uri: "wss://example.com/socket",
        path: "/api/ws",
        adapter: ReverseProxyPlugWebsocket.Adapters.Gun,
        headers: [{"authorization", "Bearer token"}],
        connect_timeout: 10_000,
        upgrade_timeout: 15_000,
        protocols: ["mqtt"],
        tls_opts: [verify: :verify_peer]
      ]

      assert {:ok, config} = Config.validate(opts)
      assert config.upstream_uri == "wss://example.com/socket"
      assert config.path == "/api/ws"
      assert config.adapter == ReverseProxyPlugWebsocket.Adapters.Gun
      assert config.headers == [{"authorization", "Bearer token"}]
      assert config.connect_timeout == 10_000
      assert config.upgrade_timeout == 15_000
      assert config.protocols == ["mqtt"]
      assert config.tls_opts == [verify: :verify_peer]
    end

    test "normalizes path to start with /" do
      opts = [upstream_uri: "ws://localhost:4000/socket", path: "socket"]

      assert {:ok, config} = Config.validate(opts)
      assert config.path == "/socket"
    end

    test "rejects missing upstream_uri" do
      opts = [path: "/socket"]
      assert {:error, "upstream_uri is required"} = Config.validate(opts)
    end

    test "rejects missing path" do
      opts = [upstream_uri: "ws://localhost:4000/socket"]
      assert {:error, "path is required"} = Config.validate(opts)
    end

    test "rejects non-string upstream_uri" do
      opts = [upstream_uri: :invalid, path: "/socket"]
      assert {:error, "upstream_uri must be a string"} = Config.validate(opts)
    end

    test "rejects non-string path" do
      opts = [upstream_uri: "ws://localhost:4000/socket", path: :invalid]
      assert {:error, "path must be a string"} = Config.validate(opts)
    end

    test "rejects URI without scheme" do
      opts = [upstream_uri: "//localhost:4000", path: "/socket"]
      assert {:error, "upstream_uri must use ws:// or wss:// scheme"} = Config.validate(opts)
    end

    test "rejects URI with invalid scheme (common mistake)" do
      opts = [upstream_uri: "localhost:4000", path: "/socket"]

      assert {:error, "upstream_uri must use ws:// or wss:// scheme, got: localhost://"} =
               Config.validate(opts)
    end

    test "rejects invalid URI scheme" do
      opts = [upstream_uri: "http://example.com", path: "/socket"]

      assert {:error, "upstream_uri must use ws:// or wss:// scheme, got: http://"} =
               Config.validate(opts)
    end

    test "rejects URI without host" do
      opts = [upstream_uri: "ws://", path: "/socket"]
      assert {:error, "upstream_uri must include a host"} = Config.validate(opts)
    end

    test "rejects invalid headers format" do
      opts = [upstream_uri: "ws://localhost:4000", path: "/socket", headers: ["invalid"]]
      assert {:error, "headers must be a list of {key, value} tuples"} = Config.validate(opts)
    end

    test "rejects invalid connect_timeout" do
      opts = [upstream_uri: "ws://localhost:4000", path: "/socket", connect_timeout: -1]
      assert {:error, "connect_timeout must be a positive integer"} = Config.validate(opts)
    end

    test "rejects invalid upgrade_timeout" do
      opts = [upstream_uri: "ws://localhost:4000", path: "/socket", upgrade_timeout: 0]
      assert {:error, "upgrade_timeout must be a positive integer"} = Config.validate(opts)
    end

    test "rejects invalid protocols" do
      opts = [upstream_uri: "ws://localhost:4000", path: "/socket", protocols: [:invalid]]
      assert {:error, "protocols must be a list of strings"} = Config.validate(opts)
    end

    test "rejects invalid tls_opts" do
      opts = [upstream_uri: "ws://localhost:4000", path: "/socket", tls_opts: "invalid"]
      assert {:error, "tls_opts must be a keyword list"} = Config.validate(opts)
    end

    test "accepts valid frame processors" do
      processor = fn frame, _state -> frame end

      opts = [
        upstream_uri: "ws://localhost:4000",
        path: "/socket",
        client_frame_processor: processor,
        server_frame_processor: processor
      ]

      assert {:ok, config} = Config.validate(opts)
      assert is_function(config.client_frame_processor, 2)
      assert is_function(config.server_frame_processor, 2)
    end

    test "uses default frame processors when not provided" do
      opts = [upstream_uri: "ws://localhost:4000", path: "/socket"]

      assert {:ok, config} = Config.validate(opts)
      assert is_function(config.client_frame_processor, 2)
      assert is_function(config.server_frame_processor, 2)

      # Default processor should pass through frames
      frame = {:text, "test"}
      assert config.client_frame_processor.(frame, %{}) == frame
      assert config.server_frame_processor.(frame, %{}) == frame
    end

    test "rejects invalid client_frame_processor" do
      opts = [
        upstream_uri: "ws://localhost:4000",
        path: "/socket",
        client_frame_processor: "not a function"
      ]

      assert {:error, "client_frame_processor must be a function with arity 2"} =
               Config.validate(opts)
    end

    test "rejects invalid server_frame_processor" do
      opts = [
        upstream_uri: "ws://localhost:4000",
        path: "/socket",
        server_frame_processor: fn x -> x end
      ]

      assert {:error, "server_frame_processor must be a function with arity 2"} =
               Config.validate(opts)
    end
  end
end
