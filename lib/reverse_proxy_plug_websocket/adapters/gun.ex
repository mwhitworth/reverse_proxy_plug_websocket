defmodule ReverseProxyPlugWebsocket.Adapters.Gun do
  @moduledoc """
    Gun adapter for WebSocket connections.

  This adapter uses the `:gun` library to establish and manage WebSocket
  connections to upstream servers. Gun is a robust HTTP/1.1, HTTP/2, and
  WebSocket client that handles connection pooling and protocol upgrades.

  Note: This adapter requires the `:gun` dependency to be available.
  Add `{:gun, "~> 2.0"}` to your `mix.exs` dependencies to use this adapter.
  """

  @behaviour ReverseProxyPlugWebsocket.WebSocketClient

  require Logger

  @type connection :: %{
          conn_pid: pid(),
          stream_ref: reference(),
          receiver_pid: pid(),
          uri: URI.t()
        }

  @impl true
  def connect(uri, headers, opts) do
    uri = normalize_uri(uri)
    receiver_target = Keyword.fetch!(opts, :receiver_target)

    # Spawn the receiver process first - it will own the Gun connection
    parent = self()

    receiver_pid =
      spawn_link(fn ->
        case connect_and_upgrade(uri, headers, opts) do
          {:ok, conn_pid, stream_ref} ->
            # Notify parent of successful connection
            send(parent, {:receiver_ready, self(), conn_pid, stream_ref})
            # Start processing Gun messages
            receiver_loop(conn_pid, stream_ref, receiver_target)

          {:error, reason} ->
            # Notify parent of failure
            send(parent, {:receiver_failed, self(), reason})
        end
      end)

    # Wait for receiver to connect
    receive do
      {:receiver_ready, ^receiver_pid, conn_pid, stream_ref} ->
        {:ok, %{conn_pid: conn_pid, stream_ref: stream_ref, receiver_pid: receiver_pid, uri: uri}}

      {:receiver_failed, ^receiver_pid, reason} ->
        {:error, reason}
    after
      Keyword.get(opts, :connect_timeout, 5000) + Keyword.get(opts, :upgrade_timeout, 5000) ->
        Process.exit(receiver_pid, :kill)
        {:error, :connection_timeout}
    end
  end

  defp connect_and_upgrade(uri, headers, opts) do
    transport = if uri.scheme == "wss", do: :tls, else: :tcp
    port = uri.port || default_port(uri.scheme)

    # Gun connection options
    gun_opts = %{
      protocols: [:http],
      transport: transport,
      tls_opts: Keyword.get(opts, :tls_opts, []),
      retry: Keyword.get(opts, :retry, 5),
      retry_timeout: Keyword.get(opts, :retry_timeout, 1000)
    }

    Logger.debug(
      "Connecting to WebSocket upstream: #{uri.scheme}://#{uri.host}:#{port}#{uri.path}"
    )

    with {:ok, conn_pid} <-
           :gun.open(
             String.to_charlist(uri.host),
             port,
             gun_opts
           ),
         {:ok, _protocol} <- :gun.await_up(conn_pid, Keyword.get(opts, :connect_timeout, 5000)) do
      # Build ws_opts, only include protocols if not empty
      ws_opts =
        case Keyword.get(opts, :protocols, []) do
          [] -> %{}
          protocols -> %{protocols: protocols}
        end

      stream_ref =
        :gun.ws_upgrade(
          conn_pid,
          uri.path || "/",
          prepare_headers(headers),
          ws_opts
        )

      # Wait for upgrade confirmation (this process will receive Gun messages)
      receive do
        {:gun_upgrade, ^conn_pid, ^stream_ref, ["websocket"], _headers} ->
          Logger.debug("WebSocket upgrade successful")
          {:ok, conn_pid, stream_ref}

        {:gun_response, ^conn_pid, ^stream_ref, _is_fin, status, _headers} ->
          :gun.close(conn_pid)
          {:error, {:upgrade_failed, status}}

        {:gun_error, ^conn_pid, ^stream_ref, reason} ->
          :gun.close(conn_pid)
          {:error, {:upgrade_error, reason}}
      after
        Keyword.get(opts, :upgrade_timeout, 5000) ->
          :gun.close(conn_pid)
          {:error, :upgrade_timeout}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to connect to upstream WebSocket: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def send_frame(%{conn_pid: conn_pid, stream_ref: stream_ref}, frame) do
    gun_frame = convert_frame_to_gun(frame)
    :gun.ws_send(conn_pid, stream_ref, gun_frame)
    :ok
  rescue
    error ->
      Logger.error("Failed to send frame: #{inspect(error)}")
      {:error, error}
  end

  @impl true
  def close(%{conn_pid: conn_pid, receiver_pid: receiver_pid}) do
    # Stop the receiver process
    Process.exit(receiver_pid, :normal)
    # Close the Gun connection
    :gun.close(conn_pid)
    :ok
  end

  # Private helpers

  defp receiver_loop(conn_pid, stream_ref, target_pid) do
    Logger.debug(
      "Gun receiver loop starting for conn=#{inspect(conn_pid)} stream=#{inspect(stream_ref)}"
    )

    receive do
      {:gun_ws, ^conn_pid, ^stream_ref, gun_frame} ->
        # Convert Gun frame to normalized frame and forward to target
        frame = convert_frame_from_gun(gun_frame)
        send(target_pid, {:upstream_frame, frame})
        receiver_loop(conn_pid, stream_ref, target_pid)

      {:gun_down, ^conn_pid, _protocol, reason, _killed_streams} ->
        # Connection went down
        Logger.debug("Gun connection down: #{inspect(reason)}")
        send(target_pid, {:upstream_closed, {:connection_down, reason}})

      # Exit receiver loop

      {:gun_error, ^conn_pid, ^stream_ref, reason} ->
        # Stream error occurred
        Logger.debug("Gun stream error: #{inspect(reason)}")
        send(target_pid, {:upstream_error, {:stream_error, reason}})
        receiver_loop(conn_pid, stream_ref, target_pid)

      {:gun_error, ^conn_pid, reason} ->
        # Connection-level error
        Logger.debug("Gun connection error: #{inspect(reason)}")
        send(target_pid, {:upstream_error, {:connection_error, reason}})
        receiver_loop(conn_pid, stream_ref, target_pid)

      other ->
        Logger.debug("Gun receiver ignoring unexpected message: #{inspect(other)}")
        receiver_loop(conn_pid, stream_ref, target_pid)
    end
  end

  defp normalize_uri(uri) when is_binary(uri) do
    URI.parse(uri)
  end

  defp normalize_uri(%URI{} = uri), do: uri

  defp default_port("ws"), do: 80
  defp default_port("wss"), do: 443

  defp prepare_headers(headers) do
    Enum.map(headers, fn
      {key, value} when is_binary(key) and is_binary(value) ->
        {String.downcase(key), value}

      {key, value} ->
        {to_string(key), to_string(value)}
    end)
  end

  defp convert_frame_to_gun({:text, text}), do: {:text, text}
  defp convert_frame_to_gun({:binary, binary}), do: {:binary, binary}
  defp convert_frame_to_gun({:ping, payload}), do: {:ping, payload}
  defp convert_frame_to_gun({:pong, payload}), do: {:pong, payload}
  defp convert_frame_to_gun(:close), do: :close

  defp convert_frame_from_gun({:text, text}), do: {:text, text}
  defp convert_frame_from_gun({:binary, binary}), do: {:binary, binary}
  defp convert_frame_from_gun({:ping, payload}), do: {:ping, payload}
  defp convert_frame_from_gun({:pong, payload}), do: {:pong, payload}
  defp convert_frame_from_gun(:close), do: :close
  defp convert_frame_from_gun({:close, code, reason}), do: {:close, code, reason}
end
