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

  def text(text, nil, encoding), do: text(text, encoding)

  def text(text, mode, encoding) when is_map(mode) do
    mode(mode) <> text(text, encoding) <> default_mode()
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

  def mode(map) when is_map(map) do
    mode(map[:zip?], map[:bold?], map[:double_height?], map[:double_width?], map[:underline?])
  end

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
    len = byte_size(data) + 3

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
      <<@gs, ?(, ?k, len::16-little, ?1, 80, 48, data::binary>>,
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

  def ht_row(
        text_spaces_list,
        width,
        mode \\ nil,
        encoding \\ @encoding,
        enable_full_ht_bug? \\ false
      ) do
    {_list, spaces_list} = Enum.unzip(text_spaces_list)
    ht_points = calculate_ht_points(spaces_list, width)

    IO.iodata_to_binary([
      set_ht(ht_points),
      ht_row_do(text_spaces_list, mode, encoding, enable_full_ht_bug?)
    ])
  end

  def ht_table(
        data,
        col_settings,
        width,
        style_settings \\ %{},
        encoding \\ @encoding,
        enable_full_ht_bug? \\ false
      ) do
    style_settings = Map.merge(%{header: nil, divide: %{}, body: nil}, style_settings)
    ht_points = col_settings |> Stream.map(& &1.spaces) |> calculate_ht_points(width)
    latest = length(col_settings) - 1

    col_settings =
      col_settings
      |> Enum.with_index()
      |> Enum.map(fn {col, index} ->
        {padding_type, latest?} =
          case index do
            0 -> {:right, false}
            ^latest -> {:left, true}
            _index -> {:both, false}
          end

        col
        |> Map.put(:padding_type, padding_type)
        |> Map.put(:index, index)
        |> Map.put(:latest?, latest?)
      end)

    header =
      Stream.map(col_settings, &{&1.label, &1})
      |> ht_table_row_do(style_settings.header, encoding, enable_full_ht_bug?)

    rows =
      Enum.map(data, fn row ->
        if is_list(row) do
          Stream.map(col_settings, fn col ->
            text = Enum.at(row, col.index, "")
            {text, col}
          end)
        else
          Stream.map(col_settings, fn col ->
            text = row[col.key] || ""
            {text, col}
          end)
        end
        |> ht_table_row_do(style_settings.body, encoding, enable_full_ht_bug?)
      end)

    IO.iodata_to_binary([
      set_ht(ht_points),
      header,
      divide(width, style_settings.divide),
      rows
    ])
  end

  def ht_table_header(
        list,
        spaces_list,
        width,
        mode \\ nil,
        encoding \\ @encoding,
        enable_full_ht_bug? \\ false
      ) do
    IO.iodata_to_binary([
      ht_table_row(list, spaces_list, mode, encoding, enable_full_ht_bug?),
      draw_line(width)
    ])
  end

  def ht_table_body(
        body,
        spaces_list,
        mode \\ nil,
        encoding \\ @encoding,
        enable_full_ht_bug? \\ false
      ) do
    for list <- body do
      ht_table_row(list, spaces_list, mode, encoding, enable_full_ht_bug?)
    end
    |> IO.iodata_to_binary()
  end

  def ht_table_row(list, spaces_list, mode, encoding \\ @encoding, enable_full_ht_bug? \\ false) do
    Enum.zip(list, spaces_list) |> ht_row_do(mode, encoding, enable_full_ht_bug?)
  end

  defp ht_row_do(text_spaces_list, mode, encoding, enable_full_ht_bug?) do
    latest = length(text_spaces_list) - 1
    multiple = if mode && mode[:double_width?], do: 2, else: 1

    {list, next_line} =
      text_spaces_list
      |> Enum.zip_with(0..latest, fn
        {text, spaces}, 0 ->
          {{text, _s}, next} = line_wrap(text, spaces, enable_full_ht_bug?, multiple)
          {{:safe, text(text, mode, encoding)}, next}

        {text, spaces}, ^latest ->
          {{text, s}, next} = line_wrap(text, spaces, false, multiple)
          {[space(s), {:safe, text(text, mode, encoding)}], next}

        {text, spaces}, _i ->
          {{text, s}, next} = line_wrap(text, spaces, enable_full_ht_bug?, multiple)
          {[space(div(s, 2)), {:safe, text(text, mode, encoding)}], next}
      end)
      |> Enum.unzip()

    if Enum.all?(next_line, &match?({"", _}, &1)) do
      # all empty
      ht_list(list, encoding)
    else
      [ht_list(list, encoding), ht_row_do(next_line, mode, encoding, enable_full_ht_bug?)]
    end
  end

  defp ht_table_row_do(col_settings, mode, encoding, enable_full_ht_bug?) do
    multiple = if mode && mode[:double_width?], do: 2, else: 1

    {list, next_line} =
      col_settings
      |> Enum.map(fn
        {text, %{padding_type: :right, spaces: spaces, latest?: latest?} = col_s} ->
          enable_full_ht_bug? = if latest?, do: false, else: enable_full_ht_bug?
          {{text, _s}, {next, n_s}} = line_wrap(text, spaces, enable_full_ht_bug?, multiple)
          {{:safe, text(text, mode, encoding)}, {next, Map.put(col_s, :spaces, n_s)}}

        {text, %{padding_type: :left, spaces: spaces, latest?: latest?} = col_s} ->
          enable_full_ht_bug? = if latest?, do: false, else: enable_full_ht_bug?
          {{text, s}, {next, n_s}} = line_wrap(text, spaces, enable_full_ht_bug?, multiple)
          {[space(s), {:safe, text(text, mode, encoding)}], {next, Map.put(col_s, :spaces, n_s)}}

        {text, %{padding_type: :both, spaces: spaces, latest?: latest?} = col_s} ->
          enable_full_ht_bug? = if latest?, do: false, else: enable_full_ht_bug?
          {{text, s}, {next, n_s}} = line_wrap(text, spaces, enable_full_ht_bug?, multiple)

          {[space(div(s, 2)), {:safe, text(text, mode, encoding)}],
           {next, Map.put(col_s, :spaces, n_s)}}
      end)
      |> Enum.unzip()

    if Enum.all?(next_line, &match?({"", _}, &1)) do
      # all empty
      ht_list(list, encoding)
    else
      [ht_list(list, encoding), ht_table_row_do(next_line, mode, encoding, enable_full_ht_bug?)]
    end
  end

  @doc "设置横向跳格位置"
  @spec set_ht(list(n :: 1..255)) :: binary
  def set_ht(list) do
    data = IO.iodata_to_binary(list)
    <<@esc, ?D, data::binary, 0>>
  end

  def divide(width, settings, encoding \\ @encoding) do
    settings = Map.merge(%{style: "-", bold?: false}, settings)

    if settings.bold? do
      bold(true) <> draw_line(width, settings.style, encoding) <> bold(false)
    else
      draw_line(width, settings.style, encoding)
    end
  end

  @doc "划线"
  def draw_line(width, c \\ "-", encoding \\ @encoding) do
    c = :iconv.convert("utf-8", encoding, c)
    IO.iodata_to_binary([List.duplicate(c, width), new_line()])
  end

  def table_custom(data, col_settings, width, style_settings \\ %{}, encoding \\ @encoding) do
    style_settings = Map.merge(%{header: nil, divide: %{}, body: nil}, style_settings)
    latest = length(col_settings) - 1

    col_settings =
      col_settings
      |> Enum.with_index()
      |> Enum.map(fn {col, index} ->
        padding_type =
          case index do
            0 -> :right
            ^latest -> :left
            _index -> :both
          end

        col |> Map.put(:padding_type, padding_type) |> Map.put(:index, index)
      end)

    header =
      Enum.map(col_settings, &{&1.label, &1.spaces, &1.padding_type})
      |> table_custom_row_do(style_settings.header, encoding)

    rows =
      Enum.map(data, fn row ->
        row =
          if is_list(row) do
            Stream.map(col_settings, fn col ->
              text = Enum.at(row, col.index, "")
              Map.put(col, :text, text)
              {text, col.spaces, col.padding_type}
            end)
          else
            Stream.map(col_settings, fn col ->
              {row[col.key] || "", col.spaces, col.padding_type}
            end)
          end
          |> table_custom_row_do(style_settings.body, encoding)

        [row, new_line()]
      end)

    IO.iodata_to_binary([
      header,
      divide(width, style_settings.divide),
      rows
    ])
  end

  def table_row(list, width, mode \\ nil, type \\ :both, encoding \\ @encoding) do
    length = length(list)
    spaces = div(width, length)
    table_custom_row(list, List.duplicate(spaces, length), mode, width, type, encoding)
  end

  def table_custom_header(
        list,
        spaces_list,
        width,
        mode \\ nil,
        type \\ :both,
        encoding \\ @encoding
      ) do
    IO.iodata_to_binary([
      bold(),
      table_custom_row(list, spaces_list, width, mode, type, encoding),
      bold(false),
      draw_line(width)
    ])
  end

  def table_custom_body(
        body,
        spaces_list,
        width,
        mode \\ nil,
        type \\ :both,
        encoding \\ @encoding
      ) do
    for list <- body do
      table_custom_row(list, spaces_list, width, mode, type, encoding)
    end
    |> IO.iodata_to_binary()
  end

  def table_custom_row(list, spaces_list, width, mode, type \\ :both, encoding \\ @encoding) do
    padding = width - Enum.sum(spaces_list)
    latest = length(spaces_list) - 1
    spaces_with_index = Enum.with_index(spaces_list)

    Enum.zip_with(spaces_with_index, list, fn
      {spaces, 0}, item -> {item, spaces + padding, :right}
      {spaces, ^latest}, item -> {item, spaces, :left}
      {spaces, _index}, item -> {item, spaces, type}
    end)
    |> table_custom_row_do(mode, encoding)
    |> IO.iodata_to_binary()
    |> Kernel.<>(new_line())
  end

  defp table_custom_row_do(col_settings, mode, encoding) do
    multiple = if mode && mode[:double_width?], do: 2, else: 1

    {list, next_line} =
      col_settings
      |> Enum.map(fn
        {text, spaces, :right} ->
          {{text, s}, next} = line_wrap(text, spaces, false, multiple)
          {text(text, encoding) <> space(s), Tuple.append(next, :right)}

        {text, spaces, :left} ->
          {{text, s}, next} = line_wrap(text, spaces, false, multiple)
          {space(s) <> text(text, encoding), Tuple.append(next, :left)}

        {text, spaces, :both} ->
          {{text, s}, next} = line_wrap(text, spaces, false, multiple)
          left_s = div(s, 2)
          right_s = s - left_s
          {space(left_s) <> text(text, encoding) <> space(right_s), Tuple.append(next, :both)}
      end)
      |> Enum.unzip()

    if Enum.all?(next_line, &match?({"", _, _}, &1)) do
      # all empty
      list
    else
      [list, table_custom_row_do(next_line, mode, encoding)]
    end
  end

  @spec padding_space(text, width :: integer, type :: :both | :left | :right) :: binary
  def padding_space(text, width, type \\ :both, encoding \\ @encoding) do
    text = text(text, encoding)
    length = byte_size(text)

    if length < width do
      spaces = width - length

      case type do
        :both ->
          left_s = div(spaces, 2)
          right_s = spaces - left_s
          space(left_s) <> text <> space(right_s)

        :left ->
          space(spaces) <> text

        :right ->
          text <> space(spaces)
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

  defp calculate_ht_points(spaces_list, width) do
    {ht_points, _} =
      Enum.reduce(spaces_list, {[], 0}, fn spaces, {acc, point} ->
        point = point + spaces

        if point >= width do
          {acc, point}
        else
          {acc ++ [point], point}
        end
      end)

    ht_points
  end

  defp space(0), do: ""

  defp space(length) do
    List.duplicate(" ", length) |> IO.iodata_to_binary()
  end

  def line_wrap(text, spaces, enable_full_ht_bug? \\ false, multiple \\ 1) do
    charlist = String.to_charlist(text)
    length = length(charlist)

    line_wrap_do(charlist, spaces, enable_full_ht_bug?, multiple)
    |> case do
      {^length, left_spaces} ->
        {{text, left_spaces}, {"", spaces}}

      {pos, left_spaces} ->
        {text, next} = String.split_at(text, pos)
        {{text, left_spaces}, {next, spaces}}
    end
  end

  # 下面注意事项不知道是否是 佳博 的 bug
  # 注意: 如果 text.length == spaces, 最后一个字会被放到下一行，否则跳格会失败
  # 最后一列 text.length == spaces, 不必将 最后一个字 放到下一行
  defp line_wrap_do(charlist, spaces, _enable_full_ht_bug? = true, _multiple = 1) do
    Enum.reduce_while(charlist, {0, spaces}, fn
      char, {pos, 2} when char > 255 ->
        {:halt, {pos, 2}}

      char, {pos, 1} when char > 255 ->
        {:halt, {pos, 1}}

      char, {pos, left_spaces} when char > 255 ->
        {:cont, {pos + 1, left_spaces - 2}}

      _char, {pos, 1} ->
        {:halt, {pos, 1}}

      _char, {pos, left_spaces} ->
        {:cont, {pos + 1, left_spaces - 1}}
    end)
  end

  defp line_wrap_do(charlist, spaces, _enable_full_ht_bug? = true, _multiple = 2) do
    Enum.reduce_while(charlist, {0, spaces}, fn
      char, {pos, 4} when char > 255 ->
        {:halt, {pos, 4}}

      char, {pos, l_s} when char > 255 and l_s in [1, 2, 3] ->
        {:halt, {pos, l_s}}

      char, {pos, left_spaces} when char > 255 ->
        {:cont, {pos + 1, left_spaces - 4}}

      _char, {pos, 2} ->
        {:halt, {pos, 2}}

      _char, {pos, 1} ->
        {:halt, {pos, 1}}

      _char, {pos, left_spaces} ->
        {:cont, {pos + 1, left_spaces - 2}}
    end)
  end

  defp line_wrap_do(charlist, spaces, _enable_full_ht_bug? = false, _multiple = 1) do
    Enum.reduce_while(charlist, {0, spaces}, fn
      char, {pos, 2} when char > 255 ->
        {:halt, {pos + 1, 0}}

      char, {pos, 1} when char > 255 ->
        {:halt, {pos, 1}}

      char, {pos, left_spaces} when char > 255 ->
        {:cont, {pos + 1, left_spaces - 2}}

      _char, {pos, 1} ->
        {:halt, {pos + 1, 0}}

      _char, {pos, left_spaces} ->
        {:cont, {pos + 1, left_spaces - 1}}
    end)
  end

  defp line_wrap_do(charlist, spaces, _enable_full_ht_bug? = false, _multiple = 2) do
    Enum.reduce_while(charlist, {0, spaces}, fn
      char, {pos, 4} when char > 255 ->
        {:halt, {pos + 1, 0}}

      char, {pos, l_s} when char > 255 and l_s in [1, 2, 3] ->
        {:halt, {pos, l_s}}

      char, {pos, left_spaces} when char > 255 ->
        {:cont, {pos + 1, left_spaces - 4}}

      _char, {pos, 2} ->
        {:halt, {pos + 1, 0}}

      _char, {pos, 1} ->
        {:halt, {pos, 1}}

      _char, {pos, left_spaces} ->
        {:cont, {pos + 1, left_spaces - 2}}
    end)
  end
end
