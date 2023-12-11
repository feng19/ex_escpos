defmodule ExEscpos.UDP do
  @moduledoc """
  跨网段配置网口 UDP 协议

  仅仅适用于佳博
  """

  @broadcast_ip {255, 255, 255, 255}

  def search do
    {:ok, socket} =
      :gen_udp.open(3000, [
        :binary,
        {:broadcast, true},
        {:active, true},
        {:reuseaddr, true},
        {:ip, {0, 0, 0, 0}}
      ])

    :gen_udp.send(socket, @broadcast_ip, 3000, "B[]G")
    loop_receive(socket, [])
  end

  defp loop_receive(socket, acc) do
    receive do
      {:udp, socket, _ip, _port, "B[]G"} ->
        loop_receive(socket, acc)

      {:udp, socket, ip, port, data} ->
        info =
          :binary.split(data, <<?;>>, [:global])
          |> Enum.reduce(%{}, fn line, info ->
            case :binary.split(line, ":") do
              [k, v] -> Map.put(info, k, v)
              _ -> info
            end
          end)

        loop_receive(socket, [%{from: %{ip: ip, port: port}, info: info} | acc])
    after
      1500 ->
        IO.puts("receive timeout")
        :gen_udp.close(socket)
        acc
    end
  end

  def reboot(ip, mac) do
    mac = trans_mac(mac)

    ip
    |> trans_ip()
    |> send_to_printer(<<"B[", mac::binary, "]EJKE02">>)
  end

  def reset(ip, mac) do
    mac = trans_mac(mac)

    ip
    |> trans_ip()
    |> send_to_printer(<<"B[", mac::binary, "]YJKE02GPRINTERGPR">>)
  end

  def set_ip(mac, ip, subnet_mask, gateway)
      when is_binary(mac) and is_binary(ip) do
    mac = trans_mac(mac)

    send_to_printer(@broadcast_ip, [
      <<"B[", mac::binary, "]YJKE02GPRINTERGPI#{ip}">>,
      <<"B[", mac::binary, "]YJKE02GPRINTERGPS#{subnet_mask}">>,
      <<"B[", mac::binary, "]YJKE02GPRINTERGPW#{gateway}">>,
      <<"B[", mac::binary, "]EJKE02">>
    ])
  end

  def set_dhcp(mac, bool, timeout) do
    mac = trans_mac(mac)
    enable = if bool, do: 1, else: 0

    send_to_printer(@broadcast_ip, [
      <<"B[", mac::binary, "]YJKE02GPRINTERGPD#{enable}">>,
      <<"B[", mac::binary, "]YJKE02GPRINTERGPt", timeout>>,
      <<"B[", mac::binary, "]EJKE02">>
    ])
  end

  def send_to_printer(ip, iodata) do
    {:ok, socket} =
      :gen_udp.open(3000, [
        :binary,
        {:broadcast, true},
        {:active, true},
        {:reuseaddr, true},
        {:ip, {0, 0, 0, 0}}
      ])

    if is_list(iodata) do
      for data <- iodata do
        :gen_udp.send(socket, ip, 3000, data)
      end
    else
      :gen_udp.send(socket, ip, 3000, iodata)
    end

    :gen_udp.close(socket)
  end

  defp trans_mac(mac) when is_binary(mac) do
    mac
    |> :binary.replace(" ", "")
    |> String.to_charlist()
    |> Stream.chunk_every(2)
    |> Enum.map(&List.to_integer(&1, 16))
    |> :erlang.list_to_binary()
  end

  defp trans_ip(ip) when is_binary(ip), do: String.to_charlist(ip)
  defp trans_ip(ip) when is_list(ip), do: ip
  defp trans_ip(ip) when is_tuple(ip), do: ip
end
