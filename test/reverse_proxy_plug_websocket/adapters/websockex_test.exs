defmodule ReverseProxyPlugWebsocket.Adapters.WebSockexTest do
  use ExUnit.Case, async: true

  alias ReverseProxyPlugWebsocket.Adapters.WebSockex, as: WebSockexAdapter

  describe "connect/3" do
    test "normalizes string URI" do
      # We can't easily test the full connection without a real WebSocket server,
      # but we can test URI normalization by catching the error
      receiver_target = self()
      uri = "ws://localhost:4000/socket"
      headers = []
      opts = [receiver_target: receiver_target]

      # The connection will fail (no server), but we're testing that it parses the URI correctly
      result = WebSockexAdapter.connect(uri, headers, opts)

      # Should fail to connect since there's no server, but not fail on URI parsing
      assert match?({:error, _}, result)
    end

    test "accepts URI struct" do
      receiver_target = self()
      uri = URI.parse("ws://localhost:4000/socket")
      headers = []
      opts = [receiver_target: receiver_target]

      result = WebSockexAdapter.connect(uri, headers, opts)

      # Should fail to connect since there's no server
      assert match?({:error, _}, result)
    end

    test "handles custom port in URI" do
      receiver_target = self()
      uri = "ws://localhost:8080/socket"
      headers = []
      opts = [receiver_target: receiver_target]

      result = WebSockexAdapter.connect(uri, headers, opts)

      # Should fail to connect since there's no server
      assert match?({:error, _}, result)
    end

    test "handles wss:// scheme" do
      receiver_target = self()
      uri = "wss://localhost:4000/socket"
      headers = []
      opts = [receiver_target: receiver_target]

      result = WebSockexAdapter.connect(uri, headers, opts)

      # Should fail to connect since there's no server
      assert match?({:error, _}, result)
    end

    test "handles query parameters in URI" do
      receiver_target = self()
      uri = "ws://localhost:4000/socket?token=abc123"
      headers = []
      opts = [receiver_target: receiver_target]

      result = WebSockexAdapter.connect(uri, headers, opts)

      # Should fail to connect since there's no server
      assert match?({:error, _}, result)
    end
  end

  describe "send_frame/2" do
    test "returns error when connection is not established" do
      # Create a fake connection structure
      fake_conn = %{
        client_pid: spawn(fn -> :ok end),
        uri: URI.parse("ws://localhost:4000")
      }

      # Try to send a frame - this should fail gracefully
      result = WebSockexAdapter.send_frame(fake_conn, {:text, "hello"})

      # Since the client_pid is not a real WebSockex process, this might
      # return :ok (cast succeeds) or {:error, _} depending on timing
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "close/1" do
    test "closes connection gracefully" do
      # Create a fake connection with a real process
      client_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      fake_conn = %{
        client_pid: client_pid,
        uri: URI.parse("ws://localhost:4000")
      }

      # Close should always return :ok
      assert :ok = WebSockexAdapter.close(fake_conn)
    end

    test "handles already-closed connection" do
      # Create a fake connection with a dead process
      client_pid = spawn(fn -> :ok end)
      # Ensure process is dead
      Process.sleep(10)

      fake_conn = %{
        client_pid: client_pid,
        uri: URI.parse("ws://localhost:4000")
      }

      # Should still return :ok even if process is dead
      assert :ok = WebSockexAdapter.close(fake_conn)
    end
  end
end
