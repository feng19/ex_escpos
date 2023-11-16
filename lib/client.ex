defmodule ExEscpos.Client do
  @moduledoc false
  use GenServer
  require Logger
  alias ExEscpos.Command

  def connect(pid, ip, port \\ 9100, page_width \\ 80, encoding \\ "GB18030")
      when is_list(ip) or is_binary(ip) do
    ip = if is_binary(ip), do: :erlang.binary_to_list(ip), else: ip
    GenServer.call(pid, {:connect, ip, port, page_width, encoding})
  end

  def status(pid), do: :sys.get_state(pid)
  def reconnect(pid), do: GenServer.call(pid, :reconnect)
  def close(pid), do: GenServer.call(pid, :close)
  def write(pid, binary), do: GenServer.cast(pid, {:write, binary})

  def check_status(ip, port \\ 4000) when is_list(ip) or is_binary(ip) do
    ip = if is_binary(ip), do: :erlang.binary_to_list(ip), else: ip
    {:ok, pid} = start_link()
    GenServer.call(pid, {:check_status, ip, port})
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init(_) do
    {:ok, %{ip: nil, port: nil, socket: nil, width: 48, page_width: 80, encoding: "GB18030"}}
  end

  def handle_call({:connect, ip, port, page_width, encoding}, _from, %{socket: nil} = state) do
    width =
      case page_width do
        58 -> 32
        80 -> 48
      end

    {:ok, socket} = :gen_tcp.connect(ip, port, [:binary, {:packet, 0}])

    {:reply, :ok,
     %{
       state
       | ip: ip,
         port: port,
         socket: socket,
         width: width,
         page_width: page_width,
         encoding: encoding
     }}
  end

  def handle_call({:connect, _ip, _port, _page_width}, _from, state) do
    {:reply, :connectd, state}
  end

  def handle_call(:reconnect, _from, state) do
    :gen_tcp.close(state.socket)
    {:ok, socket} = :gen_tcp.connect(state.ip, state.port, [:binary, {:packet, 0}])
    {:reply, :ok, %{state | ip: state.ip, port: state.port, socket: socket}}
  end

  def handle_call(:close, from, state) do
    if socket = state.socket do
      GenServer.reply(from, :ok)
      :gen_tcp.close(socket)
      {:noreply, %{state | socket: nil}}
    else
      GenServer.reply(from, :already_closed)
      {:noreply, state}
    end
  end

  def handle_call({:check_status, ip, port}, from, state) do
    {:ok, socket} = :gen_tcp.connect(ip, port, [:binary, {:packet, 0}])
    :gen_tcp.send(socket, Command.check_status())

    receive do
      {:tcp, ^socket, data} ->
        GenServer.reply(from, {:ok, Command.parse_status(data)})
    after
      4900 ->
        GenServer.reply(from, {:error, :timeout})
    end

    {:stop, :normal, state}
  end

  def handle_cast({:write, binary}, state) do
    :gen_tcp.send(state.socket, binary)
    {:noreply, state}
  end

  def handle_info({:tcp, _socket, data}, state) do
    Logger.debug("printer response #{data}")
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("printer closed")
    {:noreply, %{state | socket: nil}}
  end
end
