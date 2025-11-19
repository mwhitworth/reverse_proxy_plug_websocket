defmodule ReverseProxyPlugWebsocket do
  @moduledoc """
  A Plug for reverse proxying WebSocket connections.

  This plug detects WebSocket upgrade requests and proxies them to an upstream
  WebSocket server, maintaining bidirectional communication between the client
  and upstream.

  ## Usage

      # In your Phoenix endpoint or Plug router
      plug ReverseProxyPlugWebsocket,
        upstream_uri: "wss://example.com/socket",
        adapter: ReverseProxyPlugWebsocket.Adapters.Gun

  ## Options

    * `:upstream_uri` - (required) The WebSocket URI to proxy to (ws:// or wss://)
    * `:path` - (required) The path to proxy WebSocket requests from (e.g., "/socket")
    * `:adapter` - The WebSocket client adapter module (default: Gun)
    * `:headers` - Additional headers to forward to upstream (default: [])
    * `:connect_timeout` - Connection timeout in ms (default: 5000)
    * `:upgrade_timeout` - WebSocket upgrade timeout in ms (default: 5000)
    * `:protocols` - WebSocket subprotocols to negotiate (default: [])
    * `:tls_opts` - TLS options for wss:// connections (default: [])

  ## Examples

      # Proxy only /socket path
      plug ReverseProxyPlugWebsocket,
        upstream_uri: "ws://localhost:4000/socket",
        path: "/socket"

      # Proxy all WebSocket requests on /ws/* paths
      plug ReverseProxyPlugWebsocket,
        upstream_uri: "wss://api.example.com/ws",
        path: "/ws"

      # With custom headers and timeouts
      plug ReverseProxyPlugWebsocket,
        upstream_uri: "wss://api.example.com/ws",
        path: "/api/websocket",
        headers: [{"authorization", "Bearer token"}],
        connect_timeout: 10_000,
        protocols: ["mqtt", "v12.stomp"]

      # With custom TLS options
      plug ReverseProxyPlugWebsocket,
        upstream_uri: "wss://secure.example.com/socket",
        path: "/socket",
        tls_opts: [
          verify: :verify_peer,
          cacertfile: "/path/to/ca.pem"
        ]
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  alias ReverseProxyPlugWebsocket.Config

  @impl true
  def init(opts) do
    # Warn at compile time if adapter is specified but looks wrong
    if opts[:adapter] && !is_atom(opts[:adapter]) do
      IO.warn("adapter option should be a module name, got: #{inspect(opts[:adapter])}")
    end

    case Config.validate(opts) do
      {:ok, config} ->
        config

      {:error, reason} ->
        raise ArgumentError, "Invalid configuration: #{reason}"
    end
  end

  @impl true
  def call(conn, config) do
    if should_proxy?(conn, config) do
      Logger.info(
        "WebSocket upgrade request detected for #{conn.request_path}, proxying to #{config.upstream_uri}"
      )

      upgrade_to_websocket(conn, config)
    else
      conn
    end
  end

  # Private functions

  defp should_proxy?(conn, config) do
    websocket_upgrade_request?(conn) and path_matches?(conn, config)
  end

  defp websocket_upgrade_request?(conn) do
    # Check for WebSocket upgrade headers
    connection =
      get_req_header(conn, "connection") |> List.first() |> to_string() |> String.downcase()

    upgrade = get_req_header(conn, "upgrade") |> List.first() |> to_string() |> String.downcase()

    String.contains?(connection, "upgrade") and upgrade == "websocket"
  end

  defp path_matches?(conn, %{path: path}) do
    # Match exact path or anything under that path
    conn.request_path == path or String.starts_with?(conn.request_path, path <> "/")
  end

  defp upgrade_to_websocket(conn, config) do
    # Prepare options for the WebSocket handler
    handler_opts = [
      adapter: config.adapter,
      upstream_uri: config.upstream_uri,
      headers: merge_headers(conn, config.headers),
      connect_timeout: config.connect_timeout,
      upgrade_timeout: config.upgrade_timeout,
      protocols: config.protocols,
      tls_opts: config.tls_opts
    ]

    # Upgrade the connection using WebSockAdapter
    # This returns a halted conn, preventing further plug processing
    conn
    |> WebSockAdapter.upgrade(
      ReverseProxyPlugWebsocket.WebSocketHandler,
      handler_opts,
      timeout: config.upgrade_timeout
    )
    |> halt()
  end

  defp merge_headers(conn, additional_headers) do
    # Extract relevant headers from the client request
    client_headers = extract_client_headers(conn)

    # Merge with additional headers (additional headers take precedence)
    Enum.uniq_by(
      additional_headers ++ client_headers,
      fn {key, _value} -> String.downcase(key) end
    )
  end

  defp extract_client_headers(conn) do
    # Headers that should be forwarded to upstream
    headers_to_forward = [
      "user-agent",
      "accept-language",
      "accept-encoding",
      "cookie",
      "origin",
      "sec-websocket-protocol",
      "sec-websocket-extensions"
    ]

    Enum.flat_map(headers_to_forward, fn header ->
      case get_req_header(conn, header) do
        [] -> []
        values -> [{header, Enum.join(values, ", ")}]
      end
    end)
  end
end
