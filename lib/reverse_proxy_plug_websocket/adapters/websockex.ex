defmodule ReverseProxyPlugWebsocket.Adapters.WebSockex do
  @moduledoc """
    WebSockex adapter for WebSocket connections.

  This adapter uses the WebSockex library to establish and manage WebSocket
  connections to upstream servers. WebSockex is a pure Elixir WebSocket client
  that implements a GenServer-like callback interface.

  Note: This adapter requires the `:websockex` dependency to be available.
  Add `{:websockex, "~> 0.4.3"}` to your `mix.exs` dependencies to use this adapter.

  ## Features
  - Pure Elixir implementation
  - Automatic reconnection support (optional)
  - RFC6455 compliant
  - Simple callback-based API

  ## Comparison with Gun Adapter

  | Feature | WebSockex | Gun |
  |---------|-----------|-----|
  | Language | Pure Elixir | Erlang |
  | HTTP/2 | No | Yes |
  | Auto-reconnect | Built-in | Manual |
  | Complexity | Simple | More complex |
  """

  @behaviour ReverseProxyPlugWebsocket.WebSocketClient

  alias ReverseProxyPlugWebsocket.Adapters.WebSockexClient

  require Logger

  @type connection :: %{
          client_pid: pid(),
          uri: URI.t()
        }

  @impl true
  def connect(uri, headers, opts) do
    uri = normalize_uri(uri)
    receiver_target = Keyword.fetch!(opts, :receiver_target)

    Logger.debug(
      "Connecting to WebSocket upstream via WebSockex: #{uri.scheme}://#{uri.host}#{uri.path}"
    )

    # Build WebSocket URL
    url = build_url(uri)

    # Add receiver_target and uri to opts for WebSockexClient
    client_opts =
      opts
      |> Keyword.put(:receiver_target, receiver_target)
      |> Keyword.put(:uri, uri)

    # Start the WebSockexClient process
    case WebSockexClient.start_link(url, headers, client_opts) do
      {:ok, client_pid} ->
        Logger.debug("WebSockex client started successfully")
        {:ok, %{client_pid: client_pid, uri: uri}}

      {:error, reason} ->
        Logger.error("Failed to start WebSockex client: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def send_frame(%{client_pid: client_pid}, frame) do
    Logger.debug("Sending frame via WebSockex: #{inspect(frame)}")

    # Send frame to WebSockexClient via cast
    WebSockex.cast(client_pid, {:send_frame, frame})
    :ok
  rescue
    error ->
      Logger.error("Failed to send frame via WebSockex: #{inspect(error)}")
      {:error, error}
  end

  @impl true
  def close(%{client_pid: client_pid}) do
    Logger.debug("Closing WebSockex connection")

    # Send close message to WebSockexClient
    WebSockex.cast(client_pid, :close)
    :ok
  rescue
    error ->
      Logger.warning("Error closing WebSockex connection: #{inspect(error)}")
      :ok
  end

  # Private Helpers

  defp normalize_uri(uri) when is_binary(uri) do
    URI.parse(uri)
  end

  defp normalize_uri(%URI{} = uri), do: uri

  defp build_url(uri) do
    scheme = uri.scheme
    host = uri.host
    port = uri.port || default_port(scheme)
    path = uri.path || "/"

    # Build query string if present
    url = "#{scheme}://#{host}:#{port}#{path}"

    url =
      if uri.query do
        "#{url}?#{uri.query}"
      else
        url
      end

    url
  end

  defp default_port("ws"), do: 80
  defp default_port("wss"), do: 443
end
