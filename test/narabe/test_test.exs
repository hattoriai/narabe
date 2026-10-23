defmodule Narabe.TestTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Narabe.Test

  @endpoint NarabeTest.Endpoint

  setup do
    {:ok, view, _html} = live(build_conn(), "/board")
    %{view: view}
  end

  test "a list's move", %{view: view} do
    assert items(view, "tasks") == ["Task 1", "Task 2", "Task 3", "Task 4"]
    move(view, "tasks", 1, after: 3)
    assert_reply(view, %{ok: true})
    assert items(view, "tasks") == ["Task 2", "Task 3", "Task 1", "Task 4"]
    move(view, "tasks", [4, 2], index: 0)
    assert items(view, "tasks") == ["Task 4", "Task 2", "Task 3", "Task 1"]
  end

  test "a board's cards and columns", %{view: view} do
    move(view, "board", 1, parent: 2, before: 3)
    assert columns(view, "board") == [{"To do", ["B"]}, {"Done", ["A", "C"]}]
    move(view, "#board", 2, columns: true, before: 1)
    assert columns(view, "board") == [{"Done", ["A", "C"]}, {"To do", ["B"]}]
  end

  test "a tree: moves, refusals, children loaded, renames", %{view: view} do
    move(view, "pages", 3, parent: 1, after: 2)
    assert outline(view, "pages") == [{"Docs", 1}, {"Intro", 2}, {"Blog", 2}]
    move(view, "pages", 1, parent: 2)
    assert_reply(view, %{error: "into_itself"})
    expand(view, "pages", 3)
    assert outline(view, "pages") == [{"Docs", 1}, {"Intro", 2}, {"Blog", 2}, {"Post", 3}]
    rename(view, "pages", 4, "Hello")
    assert "Hello" in items(view, "pages")
  end

  test "a selection and a pick", %{view: view} do
    select(view, "tasks", [2, 3])
    assert view |> element("#selected") |> render() =~ "2,3"
    pick(view, "move_parent_id", 3)
    assert view |> element("#picked") |> render() =~ "3"
  end

  test "an unknown list, or one without the event", %{view: view} do
    assert_raise ArgumentError, ~r/no list/, fn -> move(view, "nope", 1) end
    assert_raise ArgumentError, ~r/no onRename/, fn -> rename(view, "tasks", 1, "x") end
  end
end
