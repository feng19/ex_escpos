defmodule ExEscpos.Client do
  @moduledoc false
  use GenServer
  require Logger
  alias ExEscpos.Command

  @default_connect_options %{
    port: 9100,
    page_width: 80,
    encoding: "GB18030",
    keep_alive: true,
    keep_alive_heartbeat_timeout: 30_000,
    disconnect_failed_max_times: 30
  }
  @connect_options [:binary, {:packet, 0}, {:send_timeout, 2500}]

  def connect(pid, ip, options \\ []) when is_list(ip) or is_binary(ip) do
    ip = if is_binary(ip), do: :erlang.binary_to_list(ip), else: ip
    options = Map.merge(@default_connect_options, Map.new(options))
    GenServer.call(pid, {:connect, ip, options})
  end

  def status(pid), do: :sys.get_state(pid)
  def reconnect(pid), do: GenServer.call(pid, :reconnect)
  def close(pid), do: GenServer.call(pid, :close)
  def write(pid, iolist), do: async_write(pid, iolist)
  def sync_write(pid, iolist), do: GenServer.call(pid, {:write, iolist})
  def sync_write_with_status(pid, iolist), do: GenServer.call(pid, {:write_with_status, iolist})
  def async_write(pid, iolist), do: GenServer.cast(pid, {:write, iolist})

  def check_status(ip, port \\ 4000) when is_list(ip) or is_binary(ip) do
    ip = if is_binary(ip), do: :erlang.binary_to_list(ip), else: ip
    {:ok, pid} = GenServer.start(__MODULE__, [])
    GenServer.call(pid, {:check_status, ip, port})
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  @impl true
  def init(_) do
    {:ok,
     %{
       ip: nil,
       port: nil,
       socket: nil,
       width: 48,
       page_width: 80,
       encoding: "GB18030",
       keep_alive_timer: nil,
       reconnect_failed_times: 0
     }}
  end

  @impl true
  def handle_call({:write, iolist}, _from, state) do
    reply = :gen_tcp.send(state.socket, iolist)
    {:reply, reply, state}
  end

  def handle_call({:write_with_status, iolist}, _from, state) do
    _reply = :gen_tcp.send(state.socket, iolist)
    {:reply, wait_callback(state.socket, 1000), state}
  end

  def handle_call({:connect, ip, options}, _from, %{socket: nil} = state) do
    Logger.info("printer connected")

    width =
      case options.page_width do
        58 -> 32
        80 -> 48
      end

    case :gen_tcp.connect(ip, options.port, @connect_options, 4500) do
      {:ok, socket} ->
        state =
          state
          |> Map.merge(options)
          |> Map.merge(%{ip: ip, socket: socket, width: width, reconnect_failed_times: 0})
          |> start_keep_alive_heartbeat()

        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:connect, _ip, _options}, _from, state) do
    {:reply, :connectd, state}
  end

  def handle_call(:reconnect, _from, state) do
    state = cancel_timer(state)
    :gen_tcp.close(state.socket)

    case :gen_tcp.connect(state.ip, state.port, @connect_options, 4500) do
      {:ok, socket} ->
        state = start_keep_alive_heartbeat(state)
        {:reply, :ok, %{state | socket: socket, reconnect_failed_times: 0}}

      error ->
        {:reply, error, %{state | socket: nil}}
    end
  end

  def handle_call(:close, from, state) do
    if socket = state.socket do
      GenServer.reply(from, :ok)
      :gen_tcp.close(socket)
      state = cancel_timer(%{state | socket: nil})
      {:noreply, state}
    else
      GenServer.reply(from, :already_closed)
      {:noreply, state}
    end
  end

  def handle_call({:check_status, ip, port}, from, state) do
    {:ok, socket} = :gen_tcp.connect(ip, port, @connect_options)
    :gen_tcp.send(socket, Command.check_status())
    reply = wait_callback(socket)
    GenServer.reply(from, reply)
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:write, iolist}, state) do
    :gen_tcp.send(state.socket, iolist)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    if byte_size(data) == 4 do
      status = Command.parse_status(data)
      Logger.debug("printer status: #{inspect(status)}")
    else
      Logger.debug("printer response #{data}")
    end

    {:noreply, state}
  end

  def handle_info(:continue_reconnect, state) do
    continue_reconnect(state)
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("printer closed")
    %{state | socket: nil} |> cancel_timer() |> continue_reconnect()
  end

  def handle_info({:tcp_error, socket, :etimedout}, state) do
    Logger.info("printer timeout")
    :gen_tcp.close(socket)
    %{state | socket: nil} |> cancel_timer() |> continue_reconnect()
  end

  def handle_info(:keep_alive_heartbeat, state) do
    if socket = state.socket do
      :gen_tcp.send(socket, Command.return_status())

      receive do
        {:tcp, ^socket, <<_>>} ->
          {:noreply, state}
      after
        1000 ->
          Logger.warning("wait printer return status timeout!!!")
          :gen_tcp.close(socket)
          %{state | socket: nil} |> cancel_timer() |> continue_reconnect()
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_continue(:reconnect, state) do
    Logger.info("reconnecting...")

    state =
      case :gen_tcp.connect(state.ip, state.port, @connect_options, 1000) do
        {:ok, socket} ->
          Logger.info("printer connected")

          %{state | socket: socket, reconnect_failed_times: 0}
          |> cancel_timer()
          |> start_keep_alive_heartbeat()

        error ->
          Logger.info("reconnect error: #{inspect(error)}")
          Process.send_after(self(), :continue_reconnect, 1000)
          %{state | reconnect_failed_times: state.reconnect_failed_times + 1}
      end

    {:noreply, state}
  end

  defp wait_callback(socket, timeout \\ 4900) do
    receive do
      {:tcp, ^socket, data} ->
        case byte_size(data) do
          1 -> {:ok, Command.parse_page_status(data)}
          4 -> {:ok, Command.parse_status(data)}
          _ -> {:ok, data}
        end
    after
      timeout -> {:error, :timeout}
    end
  end

  defp start_keep_alive_heartbeat(state) do
    if state.keep_alive do
      {:ok, tref} =
        :timer.send_interval(state.keep_alive_heartbeat_timeout, self(), :keep_alive_heartbeat)

      %{state | keep_alive_timer: tref}
    else
      %{state | keep_alive_timer: nil}
    end
  end

  defp cancel_timer(%{keep_alive_timer: nil} = state), do: state

  defp cancel_timer(%{keep_alive_timer: tref} = state) do
    :timer.cancel(tref)
    %{state | keep_alive_timer: nil}
  end

  defp continue_reconnect(state) do
    if state.keep_alive do
      if state.reconnect_failed_times < state.disconnect_failed_max_times do
        {:noreply, state, {:continue, :reconnect}}
      else
        {:noreply, %{state | keep_alive: false}}
      end
    else
      {:noreply, state}
    end
  end
end
