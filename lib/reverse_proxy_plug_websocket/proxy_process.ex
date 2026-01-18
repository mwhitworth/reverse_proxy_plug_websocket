defmodule ReverseProxyPlugWebsocket.ProxyProcess do
  @moduledoc """
  GenServer that manages the bidirectional proxy between a client WebSocket
  connection and an upstream WebSocket connection.

  This process:
  - Maintains both client and upstream connections
  - Relays frames bidirectionally
  - Handles connection lifecycle and cleanup
  - Monitors connection health
  """

  use GenServer
  require Logger

  @type state :: %{
          client_pid: pid(),
          upstream_conn: term(),
          adapter: module(),
          opts: keyword(),
          client_frame_processor: (term(), term() -> term() | :skip),
          server_frame_processor: (term(), term() -> term() | :skip)
        }

  # Client API

  @doc """
  Starts a new proxy process.

  ## Options
    - :adapter - The WebSocket client adapter module (required)
    - :upstream_uri - The upstream WebSocket URI (required)
    - :headers - Additional headers to send to upstream
    - :client_pid - The client WebSocket process PID (required)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Sends a frame from the client to be forwarded to upstream.
  """
  def client_frame(pid, frame) do
    GenServer.cast(pid, {:client_frame, frame})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    upstream_uri = Keyword.fetch!(opts, :upstream_uri)
    client_pid = Keyword.fetch!(opts, :client_pid)
    headers = Keyword.get(opts, :headers, [])
    client_frame_processor = Keyword.get(opts, :client_frame_processor, &default_processor/2)
    server_frame_processor = Keyword.get(opts, :server_frame_processor, &default_processor/2)

    Logger.debug("Starting WebSocket proxy process for #{upstream_uri}")

    # Add ourselves as the receiver target for normalized messages
    opts_with_target = Keyword.put(opts, :receiver_target, self())

    # Connect to upstream
    case adapter.connect(upstream_uri, headers, opts_with_target) do
      {:ok, upstream_conn} ->
        # Monitor client process
        Process.monitor(client_pid)

        state = %{
          client_pid: client_pid,
          upstream_conn: upstream_conn,
          adapter: adapter,
          opts: opts,
          client_frame_processor: client_frame_processor,
          server_frame_processor: server_frame_processor
        }

        # Normalized messages will arrive via handle_info
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to connect to upstream: #{inspect(reason)}")
        {:stop, {:upstream_connection_failed, reason}}
    end
  end

  @impl true
  def handle_cast({:client_frame, frame}, state) do
    Logger.debug("Processing client frame: #{inspect(frame)}")

    case state.client_frame_processor.(frame, state) do
      :skip ->
        Logger.debug("Client frame skipped")
        {:noreply, state}

      processed_frame ->
        Logger.debug("Forwarding client frame to upstream: #{inspect(processed_frame)}")

        case state.adapter.send_frame(state.upstream_conn, processed_frame) do
          :ok ->
            {:noreply, state}

          {:error, reason} ->
            Logger.error("Failed to forward frame to upstream: #{inspect(reason)}")
            {:stop, {:upstream_send_failed, reason}, state}
        end
    end
  end

  @impl true
  def handle_info({:upstream_frame, frame}, state) do
    Logger.debug("Processing upstream frame: #{inspect(frame)}")

    case state.server_frame_processor.(frame, state) do
      :skip ->
        Logger.debug("Server frame skipped")
        {:noreply, state}

      processed_frame ->
        Logger.debug("Forwarding server frame to client: #{inspect(processed_frame)}")

        case forward_to_client(state.client_pid, processed_frame) do
          :ok ->
            {:noreply, state}

          {:error, reason} ->
            Logger.error("Failed to forward frame to client: #{inspect(reason)}")
            {:stop, {:client_send_failed, reason}, state}
        end
    end
  end

  @impl true
  def handle_info({:upstream_closed, reason}, state) do
    Logger.info("Upstream connection closed: #{inspect(reason)}")
    {:stop, {:upstream_closed, reason}, state}
  end

  @impl true
  def handle_info({:upstream_error, reason}, state) do
    Logger.warning("Upstream error: #{inspect(reason)}")
    # Continue processing - non-fatal errors shouldn't kill the connection
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{client_pid: pid} = state) do
    Logger.info("Client process terminated: #{inspect(reason)}, closing upstream connection")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Proxy process terminating: #{inspect(reason)}")
    state.adapter.close(state.upstream_conn)
    :ok
  end

  # Private Helpers

  defp forward_to_client(client_pid, frame) do
    # Send frame to client WebSocket handler
    send(client_pid, {:upstream_frame, frame})
    :ok
  rescue
    error ->
      {:error, error}
  end

  defp default_processor(frame, _state), do: frame
end
