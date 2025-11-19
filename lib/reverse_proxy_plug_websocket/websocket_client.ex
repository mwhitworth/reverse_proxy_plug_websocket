defmodule ReverseProxyPlugWebsocket.WebSocketClient do
  @moduledoc """
  Behaviour defining the interface for WebSocket client adapters.

  This behaviour allows the reverse proxy to work with different WebSocket
  client implementations (Gun, WebSockex, etc.) while maintaining a consistent
  interface.

  ## Adapter Architecture

  Each adapter spawns a receiver process that handles adapter-specific messages
  (e.g., {:gun_ws, ...} for Gun) and converts them to normalized messages sent
  to the ProxyProcess:

    - {:upstream_frame, frame} - A frame was received from upstream
    - {:upstream_closed, reason} - The upstream connection was closed
    - {:upstream_error, reason} - An error occurred on the upstream connection

  This ensures ProxyProcess remains completely adapter-agnostic.
  """

  @type uri :: String.t() | URI.t()
  @type headers :: [{String.t(), String.t()}]
  @type connection :: term()
  @type frame ::
          {:text, String.t()}
          | {:binary, binary()}
          | {:ping, binary()}
          | {:pong, binary()}
          | :close
          | {:close, non_neg_integer(), binary()}
  @type opts :: keyword()

  @doc """
  Establishes a WebSocket connection to the upstream server.

  The adapter must spawn a receiver process that sends normalized messages
  to the target PID specified in opts[:receiver_target].

  ## Parameters
    - uri: The WebSocket URI to connect to (ws:// or wss://)
    - headers: Additional headers to send during the upgrade
    - opts: Adapter-specific options, including:
      - :receiver_target (required) - PID to send normalized messages to

  ## Returns
    - {:ok, connection} on success
    - {:error, reason} on failure

  ## Normalized Messages

  The receiver process must send these messages to the receiver_target:
    - {:upstream_frame, frame} - When a frame is received
    - {:upstream_closed, reason} - When the connection closes
    - {:upstream_error, reason} - When an error occurs
  """
  @callback connect(uri, headers, opts) :: {:ok, connection} | {:error, term()}

  @doc """
  Sends a WebSocket frame to the upstream server.

  ## Parameters
    - connection: The active connection
    - frame: The frame to send

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  @callback send_frame(connection, frame) :: :ok | {:error, term()}

  @doc """
  Closes the WebSocket connection.

  ## Parameters
    - connection: The connection to close

  ## Returns
    - :ok
  """
  @callback close(connection) :: :ok
end
