defmodule ReverseProxyPlugWebsocket.WebSocketHandler do
  @moduledoc """
  WebSocket handler that implements the WebSock behaviour.

  This handler manages the client-side WebSocket connection and coordinates
  with the ProxyProcess to relay frames to/from the upstream server.

  ## Frame Handling

  - Data frames (text/binary) are forwarded bidirectionally between client and upstream
  - Control frames (ping/pong) are handled by WebSock automatically on the client side,
    but we still forward them to upstream to maintain connection health checks
  - Close frames are handled automatically by WebSock, triggering terminate/2
  """

  @behaviour WebSock

  require Logger

  @impl true
  def init(opts) do
    Logger.debug("Initializing WebSocket handler with opts: #{inspect(opts)}")

    # Start the proxy process
    proxy_opts =
      [
        adapter: Keyword.fetch!(opts, :adapter),
        upstream_uri: Keyword.fetch!(opts, :upstream_uri),
        headers: Keyword.get(opts, :headers, []),
        client_pid: self()
      ] ++ opts

    case ReverseProxyPlugWebsocket.ProxyProcess.start_link(proxy_opts) do
      {:ok, proxy_pid} ->
        state = %{
          proxy_pid: proxy_pid,
          opts: opts
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start proxy process: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_in({text_or_binary, [opcode: :text]}, state) do
    Logger.debug("Received text frame from client")
    ReverseProxyPlugWebsocket.ProxyProcess.client_frame(state.proxy_pid, {:text, text_or_binary})
    {:ok, state}
  end

  @impl true
  def handle_in({binary, [opcode: :binary]}, state) do
    Logger.debug("Received binary frame from client")
    ReverseProxyPlugWebsocket.ProxyProcess.client_frame(state.proxy_pid, {:binary, binary})
    {:ok, state}
  end

  @impl true
  def handle_control({payload, [opcode: :ping]}, state) do
    Logger.debug("Received ping from client (auto-responded by WebSock)")
    # Forward to upstream to maintain connection health checks
    ReverseProxyPlugWebsocket.ProxyProcess.client_frame(state.proxy_pid, {:ping, payload})
    {:ok, state}
  end

  @impl true
  def handle_control({payload, [opcode: :pong]}, state) do
    Logger.debug("Received pong from client")
    # Forward to upstream
    ReverseProxyPlugWebsocket.ProxyProcess.client_frame(state.proxy_pid, {:pong, payload})
    {:ok, state}
  end

  @impl true
  def handle_info({:upstream_frame, frame}, state) do
    Logger.debug("Received frame from upstream: #{inspect(frame)}")

    case frame do
      {:text, text} ->
        {:push, {:text, text}, state}

      {:binary, binary} ->
        {:push, {:binary, binary}, state}

      {:ping, payload} ->
        {:push, {:ping, payload}, state}

      {:pong, payload} ->
        {:push, {:pong, payload}, state}

      :close ->
        # Normal closure from upstream
        {:stop, :normal, 1000, state}

      {:close, code, reason} ->
        # Forward the upstream close code and reason to client
        {:stop, :normal, {code, reason}, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Received unexpected message: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("WebSocket handler terminating: #{inspect(reason)}")

    # Notify proxy process of closure if it's still alive
    # The proxy process will handle closing the upstream connection
    if Process.alive?(state.proxy_pid) do
      ReverseProxyPlugWebsocket.ProxyProcess.client_frame(state.proxy_pid, :close)
    end

    :ok
  end
end
