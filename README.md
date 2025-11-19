# ReverseProxyPlugWebsocket

A Plug for reverse proxying WebSocket connections to upstream servers.

> **Note:** For HTTP reverse proxying, see [reverse_proxy_plug](https://hex.pm/packages/reverse_proxy_plug).

Unlike traditional HTTP reverse proxying, WebSocket connections are bidirectional, stateful, and long-lived. This library handles the complexity of:

- Detecting WebSocket upgrade requests
- Establishing connections to upstream WebSocket servers
- Maintaining bidirectional message flow between clients and upstream
- Managing connection lifecycle and cleanup

## Why This Library?

HTTP reverse proxying fits naturally into Plug's request/response model. WebSocket proxying requires a different architecture:

| HTTP Proxying | WebSocket Proxying |
|---------------|-------------------|
| Request → Response (stateless) | Bidirectional persistent connection |
| Single direction flow | Continuous message passing both ways |
| Fits Plug middleware model | Requires protocol upgrade + stateful relay |

This library bridges the gap, allowing you to use familiar Plug patterns for WebSocket reverse proxying.

## Installation

Add `reverse_proxy_plug_websocket` to your list of dependencies in `mix.exs`.

You must also choose at least one WebSocket client adapter:

### Option 1: Using Gun (Recommended)

```elixir
def deps do
  [
    {:reverse_proxy_plug_websocket, "~> 0.1.0"},
    {:gun, "~> 2.1"}
  ]
end
```

### Option 2: Using WebSockex

```elixir
def deps do
  [
    {:reverse_proxy_plug_websocket, "~> 0.1.0"},
    {:websockex, "~> 0.4.3"}
  ]
end
```

### Option 3: Both Adapters (Maximum Flexibility)

```elixir
def deps do
  [
    {:reverse_proxy_plug_websocket, "~> 0.1.0"},
    {:gun, "~> 2.1"},
    {:websockex, "~> 0.4.3"}
  ]
end
```

The library will automatically use Gun if available, otherwise WebSockex. You can also explicitly specify which adapter to use in your configuration.

## Usage

### Basic Example

In your Phoenix endpoint or Plug router:

```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # Proxy WebSocket connections to upstream
  plug ReverseProxyPlugWebsocket,
    upstream_uri: "wss://echo.websocket.org/"

  # Your other plugs...
end
```

### With Authentication

Forward authentication headers using runtime configuration:

```elixir
plug ReverseProxyPlugWebsocket,
  upstream_uri: "wss://api.example.com/socket",
  headers: [{"authorization", "Bearer #{Application.get_env(:my_app, :api_token)}"}]
```

### Secure Connections (WSS)

For secure WebSocket connections with custom TLS options:

```elixir
plug ReverseProxyPlugWebsocket,
  upstream_uri: "wss://secure.example.com/socket",
  tls_opts: [
    verify: :verify_peer,
    cacertfile: "/path/to/ca.pem",
    certfile: "/path/to/client-cert.pem",
    keyfile: "/path/to/client-key.pem"
  ]
```

### WebSocket Subprotocols

Negotiate specific WebSocket subprotocols:

```elixir
plug ReverseProxyPlugWebsocket,
  upstream_uri: "ws://localhost:4000/socket",
  path: "/socket",
  protocols: ["mqtt", "v12.stomp"]
```

### Custom Timeouts

Adjust connection and upgrade timeouts:

```elixir
plug ReverseProxyPlugWebsocket,
  upstream_uri: "ws://localhost:4000/socket",
  path: "/socket",
  connect_timeout: 10_000,  # 10 seconds to establish TCP connection
  upgrade_timeout: 15_000   # 15 seconds for WebSocket upgrade
```

### Choosing an Adapter

The library supports two WebSocket client adapters:

#### Using Gun Adapter (Default)

Gun is the default adapter - no configuration needed:

```elixir
plug ReverseProxyPlugWebsocket,
  upstream_uri: "wss://echo.websocket.org/"
```

Or explicitly specify it:

```elixir
plug ReverseProxyPlugWebsocket,
  upstream_uri: "wss://echo.websocket.org/",
  adapter: ReverseProxyPlugWebsocket.Adapters.Gun
```

#### Using WebSockex Adapter

WebSockex is a pure Elixir alternative:

```elixir
plug ReverseProxyPlugWebsocket,
  upstream_uri: "wss://echo.websocket.org/",
  adapter: ReverseProxyPlugWebsocket.Adapters.WebSockex
```

**When to use WebSockex:**
- You prefer pure Elixir dependencies
- Simpler debugging and error messages
- Don't need HTTP/2 support
- Want easier extensibility

**When to use Gun:**
- Need HTTP/2 support
- Want battle-tested production stability
- Require advanced connection pooling

## Configuration Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `:upstream_uri` | String | Yes | - | WebSocket URI to proxy to (ws:// or wss://) |
| `:path` | String | Yes | - | Path to proxy WebSocket requests from (e.g., "/socket") |
| `:adapter` | Module | No | Auto-detected | WebSocket client adapter (Gun or WebSockex). Defaults to Gun if available, otherwise WebSockex |
| `:headers` | List | No | `[]` | Additional headers to forward |
| `:connect_timeout` | Integer | No | `5000` | Connection timeout in milliseconds |
| `:upgrade_timeout` | Integer | No | `5000` | WebSocket upgrade timeout in ms |
| `:protocols` | List | No | `[]` | WebSocket subprotocols to negotiate |
| `:tls_opts` | Keyword | No | `[]` | TLS options for wss:// connections |

## Architecture

The library consists of several key components:

### 1. Main Plug (`ReverseProxyPlugWebsocket`)
- Detects WebSocket upgrade requests
- Validates configuration
- Initiates WebSocket upgrade

### 2. WebSocket Handler (`WebSocketHandler`)
- Manages client-side WebSocket connection
- Implements `WebSock` behaviour
- Coordinates with ProxyProcess

### 3. Proxy Process (`ProxyProcess`)
- GenServer managing bidirectional relay
- Maintains both client and upstream connections
- Handles message forwarding and lifecycle

### 4. WebSocket Client (`WebSocketClient` behaviour)
- Defines adapter interface
- Allows multiple client implementations

### 5. WebSocket Client Adapters

#### Gun Adapter (`Adapters.Gun`)
- Default adapter using `:gun` Erlang library
- Robust HTTP/2 and WebSocket support
- Battle-tested in production environments

#### WebSockex Adapter (`Adapters.WebSockex`)
- Pure Elixir WebSocket client
- Simple callback-based API
- RFC6455 compliant
- Easier to debug and extend

## How It Works

```
Client Browser          Plug Server              Upstream Server
     |                       |                          |
     |--- WS Upgrade ------->|                          |
     |                       |--- Connect Gun --------->|
     |                       |<-- WS Upgrade OK --------|
     |<-- WS Upgrade OK -----|                          |
     |                       |                          |
     |                  [ProxyProcess]                  |
     |                       |                          |
     |--- WS Frame --------->|--- Forward Frame ------->|
     |                       |                          |
     |<-- WS Frame ----------|<-- Forward Frame --------|
     |                       |                          |
```

## Examples

### Phoenix Router Integration

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :websocket do
    plug ReverseProxyPlugWebsocket,
      upstream_uri: "wss://echo.websocket.org/"
  end

  scope "/api" do
    pipe_through :websocket

    get "/socket", PageController, :index
  end
end
```

### Conditional Proxying

Only proxy specific paths:

```elixir
defmodule MyAppWeb.WebSocketProxy do
  import Plug.Conn

  def init(opts), do: opts

  def call(%{path_info: ["ws" | _]} = conn, _opts) do
    ReverseProxyPlugWebsocket.call(conn, [
      upstream_uri: "wss://echo.websocket.org/"
    ])
  end

  def call(conn, _opts), do: conn
end
```

### Dynamic Upstream Selection

Choose upstream based on request:

```elixir
defmodule MyAppWeb.DynamicProxy do
  def init(opts), do: opts

  def call(conn, _opts) do
    upstream = select_upstream(conn)

    ReverseProxyPlugWebsocket.call(conn, [
      upstream_uri: upstream
    ])
  end

  defp select_upstream(conn) do
    case get_req_header(conn, "x-region") do
      ["us-east"] -> "ws://us-east.backend.com/socket"
      ["eu-west"] -> "ws://eu-west.backend.com/socket"
      _ -> "ws://default.backend.com/socket"
    end
  end
end
```

## Development

Clone the repository and install dependencies:

```bash
git clone https://github.com/mwhitworth/reverse_proxy_plug_websocket.git
cd reverse_proxy_plug_websocket
mix deps.get
```

Run tests:

```bash
mix test
```

Generate documentation:

```bash
mix docs
```

## Testing

The library includes comprehensive tests for:

- Configuration validation
- WebSocket upgrade detection
- Header forwarding
- Connection lifecycle

Note: Integration tests require a running WebSocket server. See `test/` directory for examples.

## Limitations

- Requires Cowboy or Bandit as the web server
- WebSocket compression is not yet supported
