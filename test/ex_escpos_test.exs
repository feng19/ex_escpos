defmodule ExEscposTest do
  use ExUnit.Case
  import ExEscpos.Command
  alias ExEscpos.Client

  setup do
    ip = System.fetch_env!("PRINTER_IP")
    {:ok, pid} = Client.start_link()
    :ok = Client.connect(pid, ip)
    %{client: pid, ip: ip, width: 48}
  end

  test "check status", %{ip: ip} do
    assert {:ok, data} = Client.check_status(ip)
    IO.inspect(data, label: "Printer Status")
    assert is_map(data)
  end

  test "basic", %{client: c, width: width} do
    mode_array =
      for zip? <- [true, false],
          bold? <- [true, false],
          double_height? <- [true, false],
          double_width? <- [true, false] do
        [
          mode(bold?, zip?, double_height?, double_width?, false),
          println(
            "B:#{format_boolean(bold?)} Z:#{format_boolean(zip?)} 2H:#{format_boolean(double_height?)} 2W:#{format_boolean(double_width?)} 中文"
          )
        ]
      end

    size_array =
      for x <- 1..8 do
        [font_size(x), println("s: #{x} |!@#$%^&*()-+= abc")]
      end

    data =
      [
        init(),
        title("Basic Test"),
        println("123456789012345678901234567890123456789012345678"),
        println("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuv"),
        println("一二三四五一二三四五一二三四五一二三四五一二三四"),
        println("QRCODE:"),
        align(:center),
        qrcode("http://www.example.com"),
        new_line(),
        barcode_height(100),
        barcode_position(),
        barcode("0123456789123"),
        draw_line(width),
        align(:left),
        mode_array,
        default_mode(),
        draw_line(width),
        size_array,
        default_mode(),
        draw_line(width),
        # font style test
        bold_text("bold |!@#$%^&*()-+= abc 中文"),
        new_line(),
        underline(),
        println("underline |!@#$%^&*()-+= abc 中文"),
        double_underline(),
        println("double underline |!@#$%^&*()-+= abc 中文"),
        underline(false),
        new_line(),
        println("one line"),
        align(:left),
        table(["第一列", "中间", "最后一列"], width),
        table(["第一列", "第二列", "第三列", "第四列"], width),
        table(["第一列", "第二列", "第三列", "第四列", "第五列"], width),
        table(["第一列", "第二列", "第三列", "第四列", "第五列", "第六列"], width),
        new_line(),
        align(:left),
        println("align left"),
        align(:center),
        println("align center"),
        align(:right),
        println("align right"),
        draw_line(width, "="),
        align(:center),
        println("test end"),
        feed_cut()
      ]
      |> List.flatten()
      |> IO.iodata_to_binary()

    assert :ok = Client.sync_write(c, data)
  end

  test "hans", %{client: c, width: width} do
    array =
      for double_height? <- [true, false], double_width? <- [true, false] do
        [
          hans_mode(double_height?, double_width?, false),
          println("倍高:#{format_boolean(double_height?)}, 倍宽:#{format_boolean(double_width?)}")
        ]
      end

    data =
      [
        init(),
        title("中文测试"),
        println("我爱说中国话"),
        bold(true),
        println("(粗体)我爱说中国话"),
        bold(false),
        array,
        draw_line(width, "="),
        underline(),
        println("下划线 01 abc"),
        double_underline(),
        println("下划线 02 abc"),
        underline(false),
        align(:center),
        println("* 测试结束 END *"),
        feed_cut()
      ]
      |> List.flatten()
      |> IO.iodata_to_binary()

    assert :ok = Client.sync_write(c, data)
  end

  test "ht table", %{client: c, width: width} do
    headers = [26, 8, 6, 8]
    space_list = [0, 9, 6, 8]

    data =
      IO.iodata_to_binary([
        init(),
        title("Table Test"),
        draw_line(width),
        table_custom_header(["商品", "单价", "数量", "金额"], headers, width),
        table_custom_body(
          [
            ["素食套餐", "18", "1", "18"],
            [" 藕片（4片）", "3.8", "2", "7.6"],
            [" 腐竹（5块）", "3.8", "1", "3.8"],
            [" 海带结（5个）", "3.8", "1", "7.6"],
            ["鹌鹑蛋（4个）", "4.8", "1", "4.8"],
            ["鸡爪（3个）", "7.8", "2", "15.6"],
            ["牛肉丸（3个）", "6.8", "1", "6.8"]
          ],
          headers,
          width
        ),
        feed_cut(),
        title("HT Table Test"),
        set_ht([25, 34, 40]),
        draw_line(width),
        ht_table_header(["商品", "单价", "数量", "金额"], space_list, width),
        ht_table_body(
          [
            ["素食套餐", "18", "1", "18"],
            [" 藕片（4片）", "3.8", "2", "7.6"],
            [" 腐竹（5块）", "3.8", "1", "3.8"],
            [" 海带结（5个）", "3.8", "1", "7.6"],
            ["鹌鹑蛋（4个）", "4.8", "1", "4.8"],
            ["鸡爪（3个）", "7.8", "2", "15.6"],
            ["牛肉丸（3个）", "6.8", "1", "6.8"]
          ],
          space_list
        ),
        feed_cut()
      ])

    assert :ok = Client.sync_write(c, data)
  end

  test "bmp image", %{client: c} do
    # 24bit bmp
    bmp = BMP.read_file!("test/fixtures/logo.bmp")
    <<width::little-integer-size(32)>> = bmp.dib_header.width
    <<height::little-integer-size(32)>> = bmp.dib_header.height

    pixels =
      for <<bin::binary-size(width * 3) <- bmp.raster_data>> do
        for <<r, g, b <- bin>> do
          gray = 0.3 * r + 0.59 * g + 0.11 * b
          if gray > 127, do: 0, else: 1
        end
        |> Stream.chunk_every(8, 8, Stream.cycle([0]))
        |> Enum.map(fn [b1, b2, b3, b4, b5, b6, b7, b8] ->
          <<b1::1, b2::1, b3::1, b4::1, b5::1, b6::1, b7::1, b8::1>>
        end)
      end
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    width = byte_size(pixels) |> div(height)

    data =
      IO.iodata_to_binary([
        init(),
        title("Image Test"),
        image(width, height, pixels),
        feed_cut()
      ])

    assert :ok = Client.sync_write(c, data)
  end

  test "font style", %{client: c, width: width} do
    data =
      IO.iodata_to_binary([
        init(),
        title("Font Style Test"),
        # normal
        println("123456789012345678901234567890123456789012345678"),
        println("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuv"),
        println("一二三四五一二三四五一二三四五一二三四五一二三四"),
        draw_line(width),
        println("zip"),
        draw_line(width),
        mode(true, false, false, false, false),
        println("1234567890123456789012345678901234567890123456789012345678901234"),
        println("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl"),
        println("一二三四五一二三四五一二三四五一二三四五一二三四"),
        draw_line(width),
        println("bold"),
        draw_line(width),
        mode(false, true, false, false, false),
        println("123456789012345678901234567890123456789012345678"),
        println("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuv"),
        println("一二三四五一二三四五一二三四五一二三四五一二三四"),
        draw_line(width),
        println("double height"),
        draw_line(width),
        mode(false, false, true, false, false),
        println("123456789012345678901234567890123456789012345678"),
        println("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuv"),
        println("一二三四五一二三四五一二三四五一二三四五一二三四"),
        draw_line(width),
        println("double weight"),
        draw_line(width),
        mode(false, false, false, true, false),
        println("123456789012345678901234"),
        println("abcdefghijklmnopqrstuvwx"),
        println("一二三四五一二三四五一二"),
        draw_line(width),
        println("double height & weight"),
        draw_line(width),
        mode(false, false, true, true, false),
        println("123456789012345678901234"),
        println("abcdefghijklmnopqrstuvwx"),
        println("一二三四五一二三四五一二"),
        feed_cut()
      ])

    assert :ok = Client.sync_write(c, data)
  end

  test "sync write & return status", %{client: c} do
    data =
      IO.iodata_to_binary([
        init(),
        title("ReturnStatus Test"),
        println("123456789012345678901234567890123456789012345678"),
        println("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuv"),
        println("一二三四五一二三四五一二三四五一二三四五一二三四"),
        feed_cut(),
        return_status()
      ])

    assert {:ok, status_map} = Client.sync_write_with_status(c, data)
    assert is_map(status_map)
  end

  defp format_boolean(true), do: 1
  defp format_boolean(false), do: 0
end
