defmodule Narabe.Test do
  @moduledoc """
  Helpers for `Phoenix.LiveViewTest`, to move, open, rename and pick in
  tests with no browser.

      import Narabe.Test

      test "moves a card to Done", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/boards/1")

        move(view, "board", card.id, parent: done.id, index: 0)
        assert_reply(view, %{ok: true})
        assert {"Done", ["Write the docs", "Ship"]} in columns(view, "board")
      end

  `move/4` sends the list's `on_move` event with the move as the browser
  sends it (`Narabe.Move.to_params/1`), to the LiveView or the component of
  the list's `phx-target`; the reply is the LiveView's (`assert_reply/2`).
  The page shows what the server renders next: unlike a browser, the test
  does not move anything first.
  """

  @compile {:no_warn_undefined, [LazyHTML]}

  alias Phoenix.LiveViewTest
  alias Plug.Conn.Query

  @doc """
  Moves items (an id or a list of ids) of the list, tree or board with
  the id `list_id`, and returns the rendered LiveView.

  Options: `:after`, `:before` (a neighbour's id), `:parent` (a tree
  item's or a board column's id), `:index` (its place among its new
  siblings), and `columns: true` for a board's columns.
  """
  @spec move(struct(), String.t(), term() | [term()], keyword()) :: String.t()
  def move(view, list_id, ids, opts \\ []) do
    params =
      %Narabe.Move{
        ids: List.wrap(ids),
        parent: opts[:parent],
        after: opts[:after],
        before: opts[:before],
        index: opts[:index]
      }
      |> Narabe.Move.to_params()

    params = if opts[:columns], do: Map.put(params, "columns", true), else: params
    push(view, list_id, "onMove", params, "move/4")
  end

  @doc "Opens a tree item whose children are not loaded: sends `on_expand`."
  @spec expand(struct(), String.t(), term()) :: String.t()
  def expand(view, list_id, id),
    do: push(view, list_id, "onExpand", %{"v" => 1, "id" => to_string(id)}, "expand/3")

  @doc "Renames a tree item: sends `on_rename`."
  @spec rename(struct(), String.t(), term(), String.t()) :: String.t()
  def rename(view, list_id, id, name),
    do:
      push(
        view,
        list_id,
        "onRename",
        %{"v" => 1, "id" => to_string(id), "name" => name},
        "rename/4"
      )

  @doc "Selects items: sends `on_select`."
  @spec select(struct(), String.t(), [term()]) :: String.t()
  def select(view, list_id, ids),
    do:
      push(
        view,
        list_id,
        "onSelect",
        %{"v" => 1, "ids" => Enum.map(ids, &to_string/1)},
        "select/3"
      )

  @doc """
  Picks an item of a tree picker in a form, as a click does: the form's
  `phx-change` with the item's id. The form must have an `id`.
  """
  @spec pick(struct(), String.t(), term()) :: String.t()
  def pick(view, picker_id, id) do
    picker_id = String.trim_leading(picker_id, "#")
    html = view |> LiveViewTest.render() |> LazyHTML.from_fragment()
    picker = list!(html, picker_id, "pick/3")
    [name] = picker |> LazyHTML.query("input[data-narabe-value]") |> LazyHTML.attribute("name")

    form_id =
      html
      |> LazyHTML.query("form")
      |> Enum.find_value(fn form ->
        if not Enum.empty?(LazyHTML.query_by_id(form, picker_id)),
          do: form |> LazyHTML.attribute("id") |> List.first()
      end) || raise ArgumentError, "Narabe.Test.pick/3: #{picker_id} is not in a form with an id"

    params = URI.encode_query(%{name => to_string(id)}) |> Query.decode()
    target = name |> String.replace("]", "") |> String.split("[")

    view
    |> LiveViewTest.form("##{form_id}")
    |> LiveViewTest.render_change(Map.put(params, "_target", target))
  end

  @doc "The labels of a list's items (a board's cards, a tree's loaded items), in order."
  @spec items(struct(), String.t()) :: [String.t()]
  def items(view, list_id) do
    view |> rows(list_id) |> Enum.map(fn {label, _level} -> label end)
  end

  @doc "A tree's loaded items, in order: `{label, level}`, the top level being 1."
  @spec outline(struct(), String.t()) :: [{String.t(), pos_integer()}]
  def outline(view, list_id), do: rows(view, list_id)

  @doc "A board's columns, in order: `{label, card labels}`."
  @spec columns(struct(), String.t()) :: [{String.t(), [String.t()]}]
  def columns(view, board_id) do
    html = view |> LiveViewTest.render() |> LazyHTML.from_fragment()

    html
    |> list!(board_id, "columns/2")
    |> LazyHTML.query("[data-narabe-group]")
    |> Enum.map(fn column ->
      [label] = LazyHTML.attribute(column, "data-label")
      {label, column |> LazyHTML.query("[data-narabe-item]") |> LazyHTML.attribute("data-label")}
    end)
  end

  defp rows(view, list_id) do
    html = view |> LiveViewTest.render() |> LazyHTML.from_fragment()

    html
    |> list!(String.trim_leading(list_id, "#"), "items/2")
    |> LazyHTML.query("[data-narabe-item]")
    |> Enum.map(fn row ->
      [label] = LazyHTML.attribute(row, "data-label")
      [level] = LazyHTML.attribute(row, "data-level")
      {label, String.to_integer(level)}
    end)
  end

  # Sends a list's event (by its key in data-config) as its hook does.
  defp push(view, list_id, key, params, fun) do
    list_id = String.trim_leading(list_id, "#")
    html = view |> LiveViewTest.render() |> LazyHTML.from_fragment()
    [json] = html |> list!(list_id, fun) |> LazyHTML.attribute("data-config")

    event =
      JSON.decode!(json)[key] ||
        raise ArgumentError, "Narabe.Test.#{fun}: #{list_id} has no #{key} event"

    view |> LiveViewTest.element("##{list_id}") |> LiveViewTest.render_hook(event, params)
  end

  defp list!(html, id, fun) do
    list = LazyHTML.query(html, "##{id}[phx-hook=Narabe]")

    if Enum.empty?(list),
      do: raise(ArgumentError, "Narabe.Test.#{fun}: no list, tree or board with the id #{id}")

    list
  end
end
