defmodule Narabe.MessagesTest do
  use ExUnit.Case, async: true
  doctest Narabe.Messages

  alias Narabe.Messages.Translations

  test "every language has every key" do
    keys = Translations.english() |> Map.keys() |> Enum.sort()

    for {language, words} <- Translations.all(),
        do: assert(Enum.sort(Map.keys(words)) == keys, "#{language} lacks a key")
  end
end
