defmodule ReverseProxyPlugWebsocket.ProxyProcessTest do
  use ExUnit.Case, async: true

  alias ReverseProxyPlugWebsocket.ProxyProcess

  # Mock adapter for testing
  defmodule MockAdapter do
    @behaviour ReverseProxyPlugWebsocket.WebSocketClient

    def connect(_uri, _headers, opts) do
      receiver_target = Keyword.fetch!(opts, :receiver_target)
      test_pid = Keyword.get(opts, :test_pid)

      # Notify test process
      if test_pid do
        send(test_pid, {:connected, receiver_target})
      end

      {:ok, %{receiver: receiver_target, test_pid: test_pid}}
    end

    def send_frame(conn, frame) do
      # Notify test process of sent frame
      if conn.test_pid do
        send(conn.test_pid, {:frame_sent, frame})
      end

      :ok
    end

    def close(_conn), do: :ok
  end

  describe "frame processing" do
    test "client_frame_processor can transform frames" do
      test_pid = self()
      client_pid = spawn(fn -> Process.sleep(:infinity) end)

      processor = fn
        {:text, text}, _state -> {:text, String.upcase(text)}
        frame, _state -> frame
      end

      opts = [
        adapter: MockAdapter,
        upstream_uri: "ws://localhost:4000",
        client_pid: client_pid,
        client_frame_processor: processor,
        test_pid: test_pid
      ]

      {:ok, proxy_pid} = ProxyProcess.start_link(opts)

      # Wait for connection
      assert_receive {:connected, ^proxy_pid}

      # Send a text frame
      ProxyProcess.client_frame(proxy_pid, {:text, "hello"})

      # Verify frame was transformed
      assert_receive {:frame_sent, {:text, "HELLO"}}

      # Cleanup
      Process.exit(proxy_pid, :normal)
      Process.exit(client_pid, :normal)
    end

    test "client_frame_processor can skip frames" do
      test_pid = self()
      client_pid = spawn(fn -> Process.sleep(:infinity) end)

      processor = fn
        {:text, "drop me"}, _state -> :skip
        frame, _state -> frame
      end

      opts = [
        adapter: MockAdapter,
        upstream_uri: "ws://localhost:4000",
        client_pid: client_pid,
        client_frame_processor: processor,
        test_pid: test_pid
      ]

      {:ok, proxy_pid} = ProxyProcess.start_link(opts)

      # Wait for connection
      assert_receive {:connected, ^proxy_pid}

      # Send a frame that should be skipped
      ProxyProcess.client_frame(proxy_pid, {:text, "drop me"})

      # Verify frame was NOT sent
      refute_receive {:frame_sent, _}, 100

      # Send a frame that should pass through
      ProxyProcess.client_frame(proxy_pid, {:text, "keep me"})

      # Verify this frame was sent
      assert_receive {:frame_sent, {:text, "keep me"}}

      # Cleanup
      Process.exit(proxy_pid, :normal)
      Process.exit(client_pid, :normal)
    end

    test "server_frame_processor can transform frames" do
      client_pid = self()

      processor = fn
        {:text, text}, _state -> {:text, String.downcase(text)}
        frame, _state -> frame
      end

      opts = [
        adapter: MockAdapter,
        upstream_uri: "ws://localhost:4000",
        client_pid: client_pid,
        server_frame_processor: processor
      ]

      {:ok, proxy_pid} = ProxyProcess.start_link(opts)

      # Give process time to initialize
      Process.sleep(10)

      # Simulate upstream frame
      send(proxy_pid, {:upstream_frame, {:text, "HELLO"}})

      # Verify frame was transformed and sent to client
      assert_receive {:upstream_frame, {:text, "hello"}}

      # Cleanup
      Process.exit(proxy_pid, :normal)
    end

    test "server_frame_processor can skip frames" do
      client_pid = self()

      processor = fn
        {:text, "drop me"}, _state -> :skip
        frame, _state -> frame
      end

      opts = [
        adapter: MockAdapter,
        upstream_uri: "ws://localhost:4000",
        client_pid: client_pid,
        server_frame_processor: processor
      ]

      {:ok, proxy_pid} = ProxyProcess.start_link(opts)

      # Give process time to initialize
      Process.sleep(10)

      # Simulate upstream frame that should be skipped
      send(proxy_pid, {:upstream_frame, {:text, "drop me"}})

      # Verify frame was NOT sent to client
      refute_receive {:upstream_frame, _}, 100

      # Simulate upstream frame that should pass through
      send(proxy_pid, {:upstream_frame, {:text, "keep me"}})

      # Verify this frame was sent
      assert_receive {:upstream_frame, {:text, "keep me"}}

      # Cleanup
      Process.exit(proxy_pid, :normal)
    end

    test "uses default pass-through processor when not specified" do
      test_pid = self()
      client_pid = spawn(fn -> Process.sleep(:infinity) end)

      opts = [
        adapter: MockAdapter,
        upstream_uri: "ws://localhost:4000",
        client_pid: client_pid,
        test_pid: test_pid
      ]

      {:ok, proxy_pid} = ProxyProcess.start_link(opts)

      # Wait for connection
      assert_receive {:connected, ^proxy_pid}

      # Send a frame
      ProxyProcess.client_frame(proxy_pid, {:text, "hello"})

      # Verify frame passed through unchanged
      assert_receive {:frame_sent, {:text, "hello"}}

      # Cleanup
      Process.exit(proxy_pid, :normal)
      Process.exit(client_pid, :normal)
    end
  end
end
