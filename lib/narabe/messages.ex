defmodule Narabe.Messages do
  @moduledoc """
  The words of the lists, trees and boards: button labels, what a screen
  reader hears as items are lifted, moved and dropped, and why a move was
  refused.

  Numbers come from the browser (`Intl`), in any locale. The words are
  here, in English,
  Portuguese, Spanish, French, German, Italian, Dutch and Japanese; a
  locale with a region (`pt-BR`, `en-GB`) takes the words of its language,
  and another language gets English.

  Give a list other words with `messages`, a map from the keys of
  `keys/0` to the new words, for example to use your own Gettext
  translations:

      <.sortable_list id="tasks" items={@tasks} messages={%{"dragHandle" => gettext("Move task")}}>

  Or set them for every list in the config:

      config :narabe, messages: %{"fr" => %{"done" => "Terminé"}}

  A word may have placeholders in braces (`{n}`, `{label}`), which the
  browser fills. The keys that end in `One` and `Other` are the plural
  forms of a count, picked with the plural rules of the locale.
  """

  alias Narabe.Messages.Translations

  @doc """
  Returns the keys of the messages.

  ## Examples

      iex> "lifted" in Narabe.Messages.keys()
      true

  """
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(Translations.english())

  @doc """
  Returns the languages with built-in words.

  ## Examples

      iex> Narabe.Messages.languages()
      ["de", "en", "es", "fr", "it", "ja", "nl", "pt"]

  """
  @spec languages() :: [String.t()]
  def languages, do: Translations.all() |> Map.keys() |> Enum.sort()

  @doc """
  The words for a locale: the built-in words of its language, then the
  words of the config for the locale and for its language, then
  `overrides`. Every key has a value (English when a language lacks one).

  Raises `ArgumentError` for an override with an unknown key, so that a
  typo shows.

  ## Examples

      iex> Narabe.Messages.for_locale("pt-PT")["clear"]
      "Limpar"
      iex> Narabe.Messages.for_locale("sv")["clear"]
      "Clear"
      iex> Narabe.Messages.for_locale("en", %{"clear" => "Reset"})["clear"]
      "Reset"

  """
  @spec for_locale(String.t(), map()) :: %{String.t() => String.t()}
  def for_locale(locale, overrides \\ %{}) when is_binary(locale) do
    language = language(locale)
    config = Application.get_env(:narabe, :messages, %{})

    Translations.english()
    |> Map.merge(Map.get(Translations.all(), language, %{}))
    |> Map.merge(stringify(Map.get(config, language, %{})))
    |> Map.merge(stringify(Map.get(config, locale, %{})))
    |> Map.merge(check!(stringify(overrides || %{})))
  end

  @doc """
  The language of a locale: `"pt"` for `"pt-BR"`, `"zh"` for `"zh_Hant"`.

  ## Examples

      iex> Narabe.Messages.language("pt-BR")
      "pt"

  """
  @spec language(String.t()) :: String.t()
  def language(locale) do
    locale |> String.split(["-", "_"], parts: 2) |> hd() |> String.downcase()
  end

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp check!(overrides) do
    english = Translations.english()

    case Enum.reject(Map.keys(overrides), &Map.has_key?(english, &1)) do
      [] ->
        overrides

      unknown ->
        raise ArgumentError,
              "Narabe.Messages: unknown message keys #{inspect(unknown)}; see Narabe.Messages.keys/0"
    end
  end
end
