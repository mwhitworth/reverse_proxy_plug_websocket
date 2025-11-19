defmodule ReverseProxyPlugWebsocket.Adapters.WebSockexClient do
  @moduledoc """
    WebSockex client process that converts WebSockex callbacks to normalized messages.

  This module implements the WebSockex behaviour and acts as the receiver process
  for WebSocket connections. It converts WebSockex-specific callbacks into
  normalized messages that are sent to the ProxyProcess.

  Note: This module requires the `:websockex` dependency to be available.
  """

  if Code.ensure_loaded?(WebSockex) do
    use WebSockex
  end

  require Logger

  @type state :: %{
          receiver_target: pid(),
          uri: URI.t()
        }

  @doc """
  Starts the WebSockex client process.

  ## Options
    - :receiver_target - PID to send normalized messages to (required)
    - :uri - The WebSocket URI (for logging)
  """
  def start_link(url, headers, opts) do
    receiver_target = Keyword.fetch!(opts, :receiver_target)
    uri = Keyword.get(opts, :uri)

    state = %{
      receiver_target: receiver_target,
      uri: uri
    }

    # Build WebSockex options
    websockex_opts = build_websockex_opts(opts, headers)

    Logger.debug("Starting WebSockex client for #{inspect(url)}")

    WebSockex.start_link(url, __MODULE__, state, websockex_opts)
  end

  # WebSockex Callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.debug("WebSockex connected to #{inspect(state.uri)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame(frame, state) do
    Logger.debug("WebSockex received frame: #{inspect(frame)}")

    # Convert WebSockex frame to normalized frame
    normalized_frame = normalize_frame(frame)

    # Send to receiver target (ProxyProcess)
    send(state.receiver_target, {:upstream_frame, normalized_frame})

    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(connection_status_map, state) do
    Logger.debug("WebSockex disconnected: #{inspect(connection_status_map)}")

    # Extract reason from connection status map
    reason = Map.get(connection_status_map, :reason, :unknown)

    # Send normalized disconnect message
    send(state.receiver_target, {:upstream_closed, {:disconnected, reason}})

    # Return :ok to terminate the process (no reconnect)
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:send_frame, frame}, state) do
    Logger.debug("WebSockex sending frame: #{inspect(frame)}")

    # Convert normalized frame to WebSockex frame
    websockex_frame = denormalize_frame(frame)

    {:reply, websockex_frame, state}
  end

  @impl WebSockex
  def handle_cast(:close, state) do
    Logger.debug("WebSockex closing connection")
    {:close, state}
  end

  @impl WebSockex
  def terminate(close_reason, _state) do
    Logger.debug("WebSockex client terminating: #{inspect(close_reason)}")
    :ok
  end

  # Private Helpers

  defp build_websockex_opts(opts, headers) do
    websockex_opts = []

    # Add extra headers if provided
    websockex_opts =
      if headers != [] do
        Keyword.put(websockex_opts, :extra_headers, headers)
      else
        websockex_opts
      end

    # Add async option (default true for non-blocking connection)
    websockex_opts = Keyword.put(websockex_opts, :async, Keyword.get(opts, :async, false))

    # Add connection timeout if specified
    websockex_opts =
      if connect_timeout = Keyword.get(opts, :connect_timeout) do
        # WebSockex uses :timeout option in milliseconds
        Keyword.put(websockex_opts, :timeout, connect_timeout)
      else
        websockex_opts
      end

    # Add TLS options if specified (for wss:// connections)
    websockex_opts =
      if tls_opts = Keyword.get(opts, :tls_opts) do
        # WebSockex uses :ssl_options
        Keyword.put(websockex_opts, :ssl_options, tls_opts)
      else
        websockex_opts
      end

    # Handle WebSocket subprotocols
    websockex_opts =
      case Keyword.get(opts, :protocols, []) do
        [] ->
          websockex_opts

        protocols ->
          # Convert to header format expected by WebSockex
          protocol_header = Enum.join(protocols, ", ")
          extra_headers = Keyword.get(websockex_opts, :extra_headers, [])
          updated_headers = [{"Sec-WebSocket-Protocol", protocol_header} | extra_headers]
          Keyword.put(websockex_opts, :extra_headers, updated_headers)
      end

    websockex_opts
  end

  # Normalize WebSockex frames to our standard format
  defp normalize_frame({:text, text}), do: {:text, text}
  defp normalize_frame({:binary, binary}), do: {:binary, binary}
  defp normalize_frame({:ping, payload}), do: {:ping, payload}
  defp normalize_frame({:pong, payload}), do: {:pong, payload}
  defp normalize_frame(:close), do: :close
  defp normalize_frame({:close, code, reason}), do: {:close, code, reason}

  # Convert our normalized frames to WebSockex format
  defp denormalize_frame({:text, text}), do: {:text, text}
  defp denormalize_frame({:binary, binary}), do: {:binary, binary}
  defp denormalize_frame({:ping, payload}), do: {:ping, payload}
  defp denormalize_frame({:pong, payload}), do: {:pong, payload}
  defp denormalize_frame(:close), do: :close
  defp denormalize_frame({:close, code, reason}), do: {:close, code, reason}
end
