defmodule ExEscpos.Command do
  @moduledoc false
  @encoding "GB18030"
  @dle 16
  @esc 27
  @fs 28
  @gs 29

  @type text :: binary | {:safe, binary} | [binary | {:safe, binary}]

  def unwrap_safe({:safe, binary}) when is_binary(binary), do: binary
  def unwrap_safe(binary) when is_binary(binary), do: binary

  @doc "初始化打印机"
  def init, do: <<@esc, ?@>>

  @doc "实时状态传送"
  @spec alive_status_callback(n :: 1..4) :: binary
  def alive_status_callback(n) when n >= 1 and n <= 4, do: <<@dle, 4, n>>

  @doc "自动状态返传功能"
  @spec asb(n :: 0..255 | boolean) :: binary
  def asb(n \\ 255) do
    n =
      case n do
        false -> 0
        true -> 255
        x -> x
      end

    <<@gs, ?a, n>>
  end

  @doc "返回状态"
  def return_status(n \\ 1), do: <<@gs, ?r, n>>

  @doc "打印机状态（请使用 4000 端口）"
  def check_status, do: <<@esc, ?v>>

  @doc "打印文字"
  def text(text, encoding \\ @encoding)
  def text({:safe, text}, _encoding) when is_binary(text), do: text

  def text(list, encoding) when is_list(list) do
    Enum.map(list, &text(&1, encoding))
    |> IO.iodata_to_binary()
  end

  def text(text, encoding) when is_binary(text) do
    :iconv.convert("utf-8", encoding, text)
  end

  def bold_text(text, encoding \\ @encoding) when is_binary(text) do
    IO.iodata_to_binary([bold(), text(text, encoding), bold(false)])
  end

  def bold_text_wrap(text, encoding \\ @encoding) when is_binary(text) do
    {:safe, bold_text(text, encoding)}
  end

  @doc "打印文字"
  def print(text, encoding \\ @encoding), do: text(text, encoding)
  @doc "打印文字并换行"
  def println(text, encoding \\ @encoding), do: text(text, encoding) <> "\n"
  @doc "换行"
  def new_line, do: "\n"

  @doc "对齐方式"
  @spec align(align :: :left | :center | :right) :: binary
  def align(:left), do: <<@esc, ?a, 0>>
  def align(:center), do: <<@esc, ?a, 1>>
  def align(:right), do: <<@esc, ?a, 2>>

  @doc "默认打印模式"
  def default_mode, do: <<@esc, ?!, 0, @fs, ?!, 0>>

  @doc "打印模式"
  def mode(zip?, bold?, double_height?, double_width?, underline?) do
    n =
      if(zip?, do: 0b00000001, else: 0b00000000)
      |> then(&if bold?, do: &1 + 0b00001000, else: &1)
      |> then(&if double_height?, do: &1 + 0b00010000, else: &1)
      |> then(&if double_width?, do: &1 + 0b00100000, else: &1)
      |> then(&if underline?, do: &1 + 0b10000000, else: &1)

    <<@esc, ?!, n>> <> hans_mode(double_height?, double_width?, underline?)
  end

  def font_size_wrap(size, text, encoding \\ @encoding) do
    {:safe, IO.iodata_to_binary([font_size(size), text(text, encoding), default_mode()])}
  end

  @doc "设置字符大小"
  @spec font_size(size :: 1..8) :: binary
  def font_size(size) when size >= 1 and size <= 8 do
    case size do
      1 -> font_size(1, 2)
      2 -> font_size(1, 1)
      3 -> font_size(3, 2)
      4 -> font_size(3, 1)
      5 -> font_size(2, 2)
      6 -> font_size(2, 1)
      7 -> font_size(4, 2)
      8 -> font_size(4, 1)
    end
  end

  @doc "设置字符大小"
  @spec font_size(width :: 1..8, height :: 1..8) :: binary
  def font_size(width, height) when width >= 1 and width <= 8 and height >= 1 and height <= 8 do
    n =
      case width do
        1 -> 0b00000000
        2 -> 0b00010000
        3 -> 0b00100000
        4 -> 0b00110000
        5 -> 0b01000000
        6 -> 0b01010000
        7 -> 0b01100000
        8 -> 0b01110000
      end
      |> then(
        &case height do
          1 -> &1 + 0b00000000
          2 -> &1 + 0b00000001
          3 -> &1 + 0b00000010
          4 -> &1 + 0b00000011
          5 -> &1 + 0b00000100
          6 -> &1 + 0b00000101
          7 -> &1 + 0b00000110
          8 -> &1 + 0b00000111
        end
      )

    <<@esc, ?!, n>>
  end

  @doc """
  选择字体

  - false: 选择标准 ASCII 码字体(12 × 24)
  - true: 选择压缩 ASCII 码字体(9 × 17)
  """
  def font_mode(zip? \\ false) do
    n = if zip?, do: 1, else: 0
    <<@esc, ?M, n>>
  end

  @doc "设置下划线"
  def underline(enable? \\ true) do
    n = if enable?, do: 1, else: 0
    <<@esc, ?-, n>> <> hans_underline(enable?)
  end

  @doc "设置下划线(两点宽)"
  def double_underline do
    <<@esc, ?-, 2>> <> hans_double_underline()
  end

  @doc "设置加粗"
  def bold(enable? \\ true) do
    n = if enable?, do: 1, else: 0
    <<@esc, ?E, n>>
  end

  @doc "默认右间距"
  def default_spacing, do: <<@esc, 20, 0>>
  @doc "设置右间距"
  @spec spacing(n :: 0..255) :: binary
  def spacing(n) when n >= 0 and n <= 255, do: <<@esc, 20, n>>

  @doc "默认行距"
  def default_line_spacing, do: <<@esc, ?2>>
  @doc "设置行距"
  @spec line_spacing(n :: 0..255) :: binary
  def line_spacing(n) when n >= 0 and n <= 255, do: <<@esc, ?3, n>>

  @doc "汉字打印模式"
  def hans_mode(double_height?, double_width?, underline?) do
    n =
      if(double_width?, do: 0b00000100, else: 0b00000000)
      |> then(&if double_height?, do: &1 + 0b00001000, else: &1)
      |> then(&if underline?, do: &1 + 0b10000000, else: &1)

    <<@fs, ?!, n>>
  end

  @doc "汉字-设置下划线"
  def hans_underline(enable? \\ true) do
    n = if enable?, do: 1, else: 0
    <<@fs, ?-, n>>
  end

  @doc "汉字-设置下划线(两点宽)"
  def hans_double_underline, do: <<@fs, ?-, 2>>

  @doc """
  条形码
  type: EAN13 | "CODE128"
  data:
    - type=EAN13, 必须 12-13 位
    - type=CODE128
  """
  @spec barcode(type :: String.t(), data :: binary) :: binary
  def barcode("EAN13", data) do
    size = byte_size(data)
    <<@gs, ?k, 67, size, data::binary>>
  end

  def barcode("CODE128", data) when is_binary(data) do
    size = byte_size(data) + 2
    <<@gs, ?k, 73, size, ?{, ?B, data::binary>>
  end

  def barcode("CODE128", iodata) when is_list(iodata) do
    data = IO.iodata_to_binary(iodata)
    size = byte_size(data)
    <<@gs, ?k, 73, size, data::binary>>
  end

  @spec barcode_position(position :: nil | :top | :bottom | :both) :: binary
  def barcode_position(position \\ :bottom) do
    n =
      case position do
        nil -> 0
        :top -> 1
        :bottom -> 2
        :both -> 3
      end

    <<@gs, ?H, n>>
  end

  @spec barcode_font(zip? :: boolean) :: binary
  def barcode_font(zip? \\ false) do
    n = if zip?, do: 1, else: 0
    <<@gs, ?f, n>>
  end

  @spec barcode_weight(weight :: 2..6) :: binary
  def barcode_weight(weight \\ 3) when weight >= 2 and weight <= 6 do
    <<@gs, ?w, weight>>
  end

  @spec barcode_height(height :: 1..255) :: binary
  def barcode_height(height \\ 80) when height >= 1 and height <= 255 do
    <<@gs, ?h, height>>
  end

  @doc "二维码"
  @spec qrcode(data :: binary, qr_level :: String.t(), size :: 1..9) :: binary
  def qrcode(data, qr_level \\ "L", size \\ 3, encoding \\ @encoding)
      when size >= 1 and size <= 9 do
    data = text(data, encoding)
    pl = byte_size(data) + 3

    qr_level =
      case qr_level do
        "L" -> 48
        "M" -> 49
        "Q" -> 50
        "H" -> 51
      end

    IO.iodata_to_binary([
      # f 167
      <<@gs, ?(, ?k, 3, 0, ?1, 67, size>>,
      # f 169
      <<@gs, ?(, ?k, 3, 0, ?1, 69, qr_level>>,
      # f 180
      <<@gs, ?(, ?k, pl, 0, ?1, 80, 48, data::binary>>,
      # f 181
      <<@gs, ?(, ?k, 3, 0, ?1, 81, 48>>
    ])
  end

  def image(width, height, pixels, type \\ :normal) do
    m =
      case type do
        :normal -> 0
        :double_width -> 1
        :double_height -> 2
        :double_both -> 3
      end

    <<@gs, ?v, ?0, m, width::little-integer-size(16), height::little-integer-size(16),
      pixels::binary>>
  end

  @doc "切纸"
  @spec cut(partial? :: boolean, feed :: 0..255) :: binary
  def cut(partial? \\ false, feed \\ 3)

  def cut(partial?, 0) do
    m = if partial?, do: 1, else: 0
    <<@gs, ?V, m>>
  end

  def cut(partial?, feed) when feed >= 0 and feed <= 255 do
    m = if partial?, do: 66, else: 65
    <<@gs, ?V, m, feed>>
  end

  @doc "走纸"
  @spec feed(n :: 0..255) :: binary
  def feed(1), do: new_line()
  def feed(n) when n >= 0 and n <= 255, do: <<@esc, ?d, n>>

  def feed_cut(n \\ 1), do: feed(n) <> cut(false, n)

  @doc "蜂鸣"
  @spec beep(times :: 1..9, interval :: 1..9) :: binary
  def beep(times, interval) when times >= 1 and times <= 9 and interval >= 1 and interval <= 9,
    do: <<@esc, ?B, times, interval>>

  @doc "水平定位（跳格）"
  def ht, do: <<9>>

  def ht_list(list, encoding \\ @encoding) do
    list
    |> Enum.map(&text(&1, encoding))
    |> Enum.join(ht())
    |> Kernel.<>(new_line())
    |> IO.iodata_to_binary()
  end

  def ht_table_header(list, space_list, width, encoding \\ @encoding) do
    IO.iodata_to_binary([
      bold(),
      ht_table(list, space_list, encoding),
      bold(false),
      draw_line(width)
    ])
  end

  def ht_table_body(body, space_list, encoding \\ @encoding) do
    for list <- body do
      ht_table(list, space_list, encoding)
    end
    |> IO.iodata_to_binary()
  end

  def ht_table(list, space_list, encoding \\ @encoding) do
    latest = length(list) - 1

    space_list
    |> Enum.with_index()
    |> Enum.zip_with(list, fn
      {space, ^latest}, text ->
        text = text(text, encoding)
        padding = max(space - byte_size(text), 0)
        [List.duplicate(" ", padding), {:safe, text}]

      {space, _i}, text ->
        text = text(text, encoding)
        padding = max(space - byte_size(text), 0) |> div(2)
        [List.duplicate(" ", padding), {:safe, text}]
    end)
    |> ht_list(encoding)
  end

  @doc "设置横向跳格位置"
  @spec set_ht(l :: list(n :: 1..255)) :: binary
  def set_ht(list) do
    data = IO.iodata_to_binary(list)
    <<@esc, ?D, data::binary, 0>>
  end

  @doc "划线"
  def draw_line(width, c \\ "-", encoding \\ @encoding) do
    c = :iconv.convert("utf-8", encoding, c)
    IO.iodata_to_binary([List.duplicate(c, width), new_line()])
  end

  def table(list, width, type \\ :both, encoding \\ @encoding) do
    length = length(list)
    cell_width = div(width, length)
    table_custom(list, List.duplicate(cell_width, length), width, type, encoding)
  end

  def table_custom_header(list, headers, width, type \\ :both, encoding \\ @encoding) do
    IO.iodata_to_binary([
      bold(),
      table_custom(list, headers, width, type, encoding),
      bold(false),
      draw_line(width)
    ])
  end

  def table_custom_body(body, headers, width, type \\ :both, encoding \\ @encoding) do
    for list <- body do
      table_custom(list, headers, width, type, encoding)
    end
    |> IO.iodata_to_binary()
  end

  def table_custom(list, headers, width, type \\ :both, encoding \\ @encoding) do
    padding = width - Enum.sum(headers)
    latest = length(headers) - 1
    headers_with_index = Enum.with_index(headers)

    Enum.zip_with(headers_with_index, list, fn
      {cell_length, 0}, item -> padding(item, cell_length + padding, :right, encoding)
      {cell_length, ^latest}, item -> padding(item, cell_length, :left, encoding)
      {cell_length, _index}, item -> padding(item, cell_length, type, encoding)
    end)
    |> IO.iodata_to_binary()
    |> Kernel.<>(new_line())
  end

  @spec padding(text, width :: integer, type :: :both | :left | :right) :: binary
  def padding(text, width, type \\ :both, encoding \\ @encoding) do
    text = text(text, encoding)
    length = byte_size(text)

    if length < width do
      case width - length do
        1 ->
          text <> " "

        spaces ->
          case type do
            :both ->
              left_s = div(spaces, 2)
              right_s = spaces - left_s
              [List.duplicate(" ", left_s), text | List.duplicate(" ", right_s)]

            :left ->
              [List.duplicate(" ", spaces), text]

            :right ->
              [text | List.duplicate(" ", spaces)]
          end
          |> IO.iodata_to_binary()
      end
    else
      text
    end
  end

  def title(text, encoding \\ @encoding) do
    IO.iodata_to_binary([
      mode(false, true, true, true, false),
      align(:center),
      println(text, encoding),
      align(:left),
      new_line(),
      default_mode()
    ])
  end

  def parse_status(<<b1, b2, b3, _b4>>) do
    <<_::2, cash_box::1, online::1, _::1, open::1, feed::1, _::1>> = <<b1>>
    <<_::3, cut::1, _::1, error_abort::1, error::1, _::1>> = <<b2>>
    <<page_not_enough::2, page::2, _::4>> = <<b3>>
    open_or_close? = &match?(1, &1)

    %{
      cash_box: open_or_close?.(cash_box),
      online: not open_or_close?.(online),
      open: open_or_close?.(open),
      feed: open_or_close?.(feed),
      cut: open_or_close?.(cut),
      error_abort: open_or_close?.(error_abort),
      error: open_or_close?.(error),
      page_not_enough: page_not_enough == 3,
      page: page == 0
    }
  end

  def parse_page_status(<<page_not_enough::2, page::2, _::4>>) do
    %{page_not_enough: page_not_enough == 3, page: page == 0}
  end
end
