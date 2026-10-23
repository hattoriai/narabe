defmodule Narabe.Position do
  @moduledoc """
  Position keys: a text per item that sorts between its neighbours, so
  that moving an item writes that one row, and two people moving at once
  both land.

      iex> Narabe.Position.between(nil, nil)
      "a0"
      iex> Narabe.Position.between("a0", nil)
      "a1"
      iex> Narabe.Position.between("a0", "a1")
      "a0V"
      iex> Narabe.Position.between(nil, "a0")
      "Zz"

  It is fractional indexing, as rocicorp's `fractional-indexing` (CC0):
  base 62 (`0-9A-Za-z`), compared byte by byte. A key is an integer part
  (a head letter that says its length, then digits) and a fraction that
  never ends in `0`. Keys after the last count up (`"a1"`, `"a2"`, …,
  `"b00"`), keys before the first count down, and a key between two close
  ones grows a fraction. The browser's twin (`assets/src/position.ts`) gives
  the same keys, held to the same answers by one fixture.

  ## In the database

  Keys compare byte by byte, which is not every database's default:

    * Postgres: the column needs `COLLATE "C"` (`Narabe.Migration.position/2`
      adds it); a text column in a locale's collation sorts `"a"` and `"B"`
      the other way.
    * MySQL: a binary collation (`utf8mb4_bin`).
    * SQLite: its default (`BINARY`) is right.

  Two moves into the same gap at the same moment get the same key: order
  by the key, then by id (`Narabe.Ecto.ordered/2`), and the order is the
  same on every screen. Keys grow only when items keep landing in the same
  gap; `Narabe.Ecto.rebalance/4` spreads a list's keys out again.
  """

  @digits "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @digit_list String.graphemes(@digits)
  @index Map.new(Enum.with_index(@digit_list))
  @zero "0"
  @last "z"
  @smallest_integer "A" <> String.duplicate("0", 26)

  @typedoc "A position key."
  @type t :: String.t()

  @doc """
  A key between `a` and `b`; `nil` is the start or the end.

  Raises `ArgumentError` when `a` is not before `b`, or either is not a key.
  """
  @spec between(t() | nil, t() | nil) :: t()
  def between(nil, nil), do: "a0"

  def between(a, b) do
    if a, do: check!(a)
    if b, do: check!(b)
    if a && b && a >= b, do: raise(ArgumentError, "Narabe: #{a} is not before #{b}")
    do_between(a, b)
  end

  defp do_between(nil, b) do
    ib = integer_part(b)
    fb = binary_part(b, byte_size(ib), byte_size(b) - byte_size(ib))

    cond do
      ib == @smallest_integer -> ib <> midpoint("", fb)
      ib < b -> ib
      true -> decrement(ib) || raise ArgumentError, "Narabe: no key before the smallest"
    end
  end

  defp do_between(a, nil) do
    ia = integer_part(a)
    increment(ia) || ia <> midpoint(fraction(a, ia), nil)
  end

  defp do_between(a, b) do
    ia = integer_part(a)
    ib = integer_part(b)

    if ia == ib do
      ia <> midpoint(fraction(a, ia), fraction(b, ib))
    else
      key = increment(ia) || raise ArgumentError, "Narabe: no key after the largest"
      if key < b, do: key, else: ia <> midpoint(fraction(a, ia), nil)
    end
  end

  @doc """
  `n` keys between `a` and `b`, in order, spread so that none grows long:
  for several items moved at once, or a list's keys written anew.

      iex> Narabe.Position.between_many(nil, nil, 3)
      ["a0", "a1", "a2"]
      iex> Narabe.Position.between_many("a0", "a1", 3)
      ["a0G", "a0V", "a0l"]
  """
  @spec between_many(t() | nil, t() | nil, non_neg_integer()) :: [t()]
  def between_many(_a, _b, n) when n <= 0, do: []
  def between_many(a, b, 1), do: [between(a, b)]

  def between_many(a, nil, n) do
    first = between(a, nil)
    Enum.scan(1..(n - 1)//1, first, fn _, c -> between(c, nil) end) |> then(&[first | &1])
  end

  def between_many(nil, b, n) do
    first = between(nil, b)

    Enum.scan(1..(n - 1)//1, first, fn _, c -> between(nil, c) end)
    |> then(&[first | &1])
    |> Enum.reverse()
  end

  def between_many(a, b, n) do
    middle = div(n, 2)
    c = between(a, b)
    between_many(a, c, middle) ++ [c | between_many(c, b, n - middle - 1)]
  end

  @doc """
  Whether a text is a position key.

      iex> Narabe.Position.valid?("a0V")
      true
      iex> Narabe.Position.valid?("a0V0")
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(key) when is_binary(key) do
    check!(key)
    true
  rescue
    ArgumentError -> false
  end

  def valid?(_other), do: false

  # -- The parts of a key ----------------------------------------------------

  defp check!(key) do
    unless key != "" and key != @smallest_integer and
             key |> String.graphemes() |> Enum.all?(&Map.has_key?(@index, &1)) do
      raise ArgumentError, "Narabe: not a position key: #{inspect(key)}"
    end

    integer = integer_part(key)

    if String.ends_with?(fraction(key, integer), @zero),
      do: raise(ArgumentError, "Narabe: not a position key: #{inspect(key)}")

    :ok
  end

  defp integer_length(<<head>>) when head in ?a..?z, do: head - ?a + 2
  defp integer_length(<<head>>) when head in ?A..?Z, do: ?Z - head + 2

  defp integer_length(head),
    do: raise(ArgumentError, "Narabe: not a position key head: #{inspect(head)}")

  defp integer_part(key) do
    length = integer_length(binary_part(key, 0, 1))

    if length > byte_size(key),
      do: raise(ArgumentError, "Narabe: not a position key: #{inspect(key)}")

    binary_part(key, 0, length)
  end

  defp fraction(key, integer),
    do: binary_part(key, byte_size(integer), byte_size(key) - byte_size(integer))

  defp digit(char), do: Map.fetch!(@index, char)
  defp char(index), do: Enum.at(@digit_list, index)

  # The midpoint of two fractions; `b` nil is the end.
  defp midpoint(a, b) do
    if b != nil and a >= b, do: raise(ArgumentError, "Narabe: #{a} is not before #{b}")

    if String.ends_with?(a, @zero) or (b != nil and String.ends_with?(b, @zero)),
      do: raise(ArgumentError, "Narabe: a fraction ends in 0")

    case b && common_prefix(a, b, 0) do
      n when is_integer(n) and n > 0 ->
        binary_part(b, 0, n) <>
          midpoint(drop(a, n), binary_part(b, n, byte_size(b) - n))

      _none ->
        midpoint_digits(a, b)
    end
  end

  defp midpoint_digits(a, b) do
    digit_a = if a == "", do: 0, else: digit(binary_part(a, 0, 1))
    digit_b = if b == nil, do: 62, else: digit(binary_part(b, 0, 1))

    cond do
      digit_b - digit_a > 1 -> char(round((digit_a + digit_b) / 2))
      b != nil and byte_size(b) > 1 -> binary_part(b, 0, 1)
      true -> char(digit_a) <> midpoint(drop(a, 1), nil)
    end
  end

  # How many leading digits a (padded with 0) and b share.
  defp common_prefix(a, b, n) do
    if n < byte_size(b) and at(a, n) == binary_part(b, n, 1),
      do: common_prefix(a, b, n + 1),
      else: n
  end

  defp at(text, n) when n < byte_size(text), do: binary_part(text, n, 1)
  defp at(_text, _n), do: @zero

  defp drop(text, n) when n >= byte_size(text), do: ""
  defp drop(text, n), do: binary_part(text, n, byte_size(text) - n)

  defp increment(<<head, digits::binary>>) do
    case carry(String.graphemes(digits), :up) do
      {:done, digits} -> <<head>> <> Enum.join(digits)
      {:over, digits} -> grow(head, digits)
    end
  end

  defp grow(?Z, _digits), do: "a" <> @zero
  defp grow(?z, _digits), do: nil

  defp grow(head, digits) do
    next = head + 1
    digits = if next > ?a, do: digits ++ [@zero], else: Enum.drop(digits, -1)
    <<next>> <> Enum.join(digits)
  end

  defp decrement(<<head, digits::binary>>) do
    case carry(String.graphemes(digits), :down) do
      {:done, digits} -> <<head>> <> Enum.join(digits)
      {:over, digits} -> shrink(head, digits)
    end
  end

  defp shrink(?a, _digits), do: "Z" <> @last
  defp shrink(?A, _digits), do: nil

  defp shrink(head, digits) do
    previous = head - 1
    digits = if previous < ?Z, do: digits ++ [@last], else: Enum.drop(digits, -1)
    <<previous>> <> Enum.join(digits)
  end

  # Adds or takes 1 from the last digit, carrying left; :over when it
  # carries out of the first.
  defp carry(digits, direction) do
    {digits, over} =
      digits
      |> Enum.reverse()
      |> Enum.map_reduce(true, fn
        d, false -> {d, false}
        d, true -> step(d, direction)
      end)

    {if(over, do: :over, else: :done), Enum.reverse(digits)}
  end

  defp step(d, :up) do
    case digit(d) + 1 do
      62 -> {@zero, true}
      n -> {char(n), false}
    end
  end

  defp step(d, :down) do
    case digit(d) - 1 do
      -1 -> {@last, true}
      n -> {char(n), false}
    end
  end
end
