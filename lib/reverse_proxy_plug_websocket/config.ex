defmodule ReverseProxyPlugWebsocket.Config do
  @moduledoc """
  Configuration validation and normalization for the WebSocket reverse proxy.
  """

  @type config :: %{
          upstream_uri: String.t(),
          path: String.t(),
          adapter: module(),
          headers: [{String.t(), String.t()}],
          connect_timeout: pos_integer(),
          upgrade_timeout: pos_integer(),
          protocols: [String.t()],
          tls_opts: keyword(),
          client_frame_processor: (term(), term() -> term() | :skip),
          server_frame_processor: (term(), term() -> term() | :skip)
        }

  @doc """
  Validates and normalizes configuration options.

  ## Required Options
    - :upstream_uri - The WebSocket URI to proxy to (ws:// or wss://)
    - :path - The path to proxy WebSocket requests from (e.g., "/socket")

  ## Optional Options
    - :adapter - The WebSocket client adapter (auto-detected based on available dependencies)
                 Available adapters: Gun, WebSockex
                 Defaults to Gun if available, otherwise WebSockex
    - :headers - Additional headers to forward
    - :connect_timeout - Connection timeout in ms (default: 5000)
    - :upgrade_timeout - WebSocket upgrade timeout in ms (default: 5000)
    - :protocols - WebSocket subprotocols (default: [])
    - :tls_opts - TLS options for wss:// connections (default: [])
    - :client_frame_processor - Function to process/drop client frames (frame, state) -> frame | :skip
    - :server_frame_processor - Function to process/drop server frames (frame, state) -> frame | :skip
  """
  @spec validate(keyword()) :: {:ok, config()} | {:error, String.t()}
  def validate(opts) do
    with {:ok, upstream_uri} <- validate_upstream_uri(opts),
         {:ok, path} <- validate_path(opts),
         {:ok, adapter} <- validate_adapter(opts),
         {:ok, headers} <- validate_headers(opts),
         {:ok, timeouts} <- validate_timeouts(opts),
         {:ok, protocols} <- validate_protocols(opts),
         {:ok, tls_opts} <- validate_tls_opts(opts),
         {:ok, client_processor} <- validate_frame_processor(opts, :client_frame_processor),
         {:ok, server_processor} <- validate_frame_processor(opts, :server_frame_processor) do
      config = %{
        upstream_uri: upstream_uri,
        path: path,
        adapter: adapter,
        headers: headers,
        connect_timeout: timeouts.connect,
        upgrade_timeout: timeouts.upgrade,
        protocols: protocols,
        tls_opts: tls_opts,
        client_frame_processor: client_processor,
        server_frame_processor: server_processor
      }

      {:ok, config}
    end
  end

  # Private validation functions

  defp validate_upstream_uri(opts) do
    case Keyword.fetch(opts, :upstream_uri) do
      {:ok, uri} when is_binary(uri) ->
        case URI.parse(uri) do
          %URI{scheme: scheme} when scheme not in ["ws", "wss"] ->
            {:error, "upstream_uri must use ws:// or wss:// scheme, got: #{scheme}://"}

          %URI{host: nil} ->
            {:error, "upstream_uri must include a host"}

          %URI{host: ""} ->
            {:error, "upstream_uri must include a host"}

          %URI{scheme: scheme, host: host} when scheme in ["ws", "wss"] and not is_nil(host) ->
            {:ok, uri}

          _ ->
            {:error, "invalid upstream_uri format"}
        end

      {:ok, _} ->
        {:error, "upstream_uri must be a string"}

      :error ->
        {:error, "upstream_uri is required"}
    end
  end

  defp validate_path(opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} when is_binary(path) ->
        # Ensure path starts with /
        normalized_path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
        {:ok, normalized_path}

      {:ok, _} ->
        {:error, "path must be a string"}

      :error ->
        {:error, "path is required"}
    end
  end

  defp validate_adapter(opts) do
    case Keyword.fetch(opts, :adapter) do
      {:ok, adapter} ->
        # User explicitly specified an adapter
        validate_explicit_adapter(adapter)

      :error ->
        # Auto-detect adapter
        detect_adapter()
    end
  end

  defp validate_explicit_adapter(adapter) when is_atom(adapter) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        {:error,
         "adapter module #{inspect(adapter)} not found. Did you add it to your dependencies?"}

      not implements_websocket_client?(adapter) ->
        {:error,
         "adapter module #{inspect(adapter)} does not implement the WebSocketClient behaviour"}

      true ->
        {:ok, adapter}
    end
  end

  defp validate_explicit_adapter(adapter) do
    {:error, "adapter must be a module name (atom), got: #{inspect(adapter)}"}
  end

  # Automatically detect which adapter to use based on available dependencies
  defp detect_adapter do
    cond do
      implements_websocket_client?(ReverseProxyPlugWebsocket.Adapters.Gun) ->
        {:ok, ReverseProxyPlugWebsocket.Adapters.Gun}

      implements_websocket_client?(ReverseProxyPlugWebsocket.Adapters.WebSockex) ->
        {:ok, ReverseProxyPlugWebsocket.Adapters.WebSockex}

      true ->
        {:error, "no WebSocket adapter found. Please add :gun or :websockex to your dependencies"}
    end
  end

  defp implements_websocket_client?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :connect, 3) and
      function_exported?(module, :send_frame, 2) and
      function_exported?(module, :close, 1)
  end

  defp validate_headers(opts) do
    headers = Keyword.get(opts, :headers, [])

    if valid_headers?(headers) do
      {:ok, headers}
    else
      {:error, "headers must be a list of {key, value} tuples"}
    end
  end

  defp validate_timeouts(opts) do
    connect = Keyword.get(opts, :connect_timeout, 5000)
    upgrade = Keyword.get(opts, :upgrade_timeout, 5000)

    cond do
      not is_integer(connect) or connect <= 0 ->
        {:error, "connect_timeout must be a positive integer"}

      not is_integer(upgrade) or upgrade <= 0 ->
        {:error, "upgrade_timeout must be a positive integer"}

      true ->
        {:ok, %{connect: connect, upgrade: upgrade}}
    end
  end

  defp validate_protocols(opts) do
    protocols = Keyword.get(opts, :protocols, [])

    if is_list(protocols) and Enum.all?(protocols, &is_binary/1) do
      {:ok, protocols}
    else
      {:error, "protocols must be a list of strings"}
    end
  end

  defp validate_tls_opts(opts) do
    tls_opts = Keyword.get(opts, :tls_opts, [])

    if Keyword.keyword?(tls_opts) do
      {:ok, tls_opts}
    else
      {:error, "tls_opts must be a keyword list"}
    end
  end

  defp valid_headers?(headers) when is_list(headers) do
    Enum.all?(headers, fn
      {key, value} when is_binary(key) and is_binary(value) -> true
      _ -> false
    end)
  end

  defp valid_headers?(_), do: false

  defp validate_frame_processor(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, processor} when is_function(processor, 2) ->
        {:ok, processor}

      {:ok, _} ->
        {:error, "#{key} must be a function with arity 2"}

      :error ->
        # Use default pass-through processor
        {:ok, &default_frame_processor/2}
    end
  end

  defp default_frame_processor(frame, _state), do: frame
end
