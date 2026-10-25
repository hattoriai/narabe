defmodule Narabe.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Narabe.Components

  alias Narabe.Ecto.Mixed

  defp config(html, selector \\ "[phx-hook=Narabe]") do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("data-config")
    |> hd()
    |> JSON.decode!()
  end

  defp attrs(html, selector, name) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  end

  test "a list: its items, in order, with their ids and labels" do
    assigns = %{items: [%{id: 1, title: "Write"}, %{id: 2, title: "Ship"}]}

    html =
      rendered_to_string(~H"""
      <.sortable_list id="tasks" items={@items} on_move="move" label="Tasks" />
      """)

    assert attrs(html, "[data-narabe-item]", "data-id") == ["1", "2"]
    assert attrs(html, "[data-narabe-item]", "data-label") == ["Write", "Ship"]
    assert attrs(html, "[data-narabe-item]", "role") == ["option", "option"]
    assert attrs(html, "[data-narabe-chrome]", "phx-update") == ["ignore"]
    c = config(html)
    assert c["kind"] == "list"
    assert c["onMove"] == "move"
    refute c["rules"]["nest"]
    assert c["messages"]["dragHandle"]
  end

  test "a list's item slot, handle, and locked items" do
    assigns = %{items: [%{id: 1, name: "A", lock: "Ana"}, %{id: 2, name: "B", lock: nil}]}

    html =
      rendered_to_string(~H"""
      <.sortable_list id="l" items={@items} on_move="m" handle item_locked={:lock} multiple>
        <:item :let={item}><b>{item.name}!</b></:item>
      </.sortable_list>
      """)

    assert html =~ "<b>A!</b>"
    assert length(attrs(html, "[data-narabe-handle]", "class")) == 2
    assert attrs(html, "[data-locked]", "data-locked") == ["Ana"]
    assert attrs(html, "[role=listbox]", "aria-multiselectable") == ["true"]
    assert config(html)["multiple"] == true
  end

  test "lists of a group: the group, what each accepts, a list's parent, on_leave" do
    assigns = %{tasks: [%{id: 1, title: "Write"}], cards: [], columns: [%{id: 7, name: "Done"}]}

    html =
      rendered_to_string(~H"""
      <.sortable_list id="launch" items={@tasks} parent={3} group="tasks" accept={["board", :someday]} on_move="m" on_leave="left" />
      <.board id="board" columns={@columns} cards={@cards} group="tasks" on_move="m" />
      """)

    launch = config(html, "#launch")
    assert launch["group"] == "tasks"
    assert launch["accept"] == ["board", "someday"]
    assert launch["parent"] == "3"
    assert launch["onLeave"] == "left"
    board = config(html, "#board")
    assert board["group"] == "tasks"
    refute Map.has_key?(board, "accept")
    refute Map.has_key?(board, "parent")
    assert launch["messages"]["otherLists"]
  end

  test "a tree: flat rows with levels, parents and the tree's aria" do
    assigns = %{
      items: [
        %{id: 1, name: "Docs", parent_id: nil},
        %{id: 2, name: "Intro", parent_id: 1},
        %{id: 3, name: "API", parent_id: nil}
      ]
    }

    html =
      rendered_to_string(~H"""
      <.tree id="pages" items={@items} on_move="move" expanded={[1]} filter on_rename="rename" />
      """)

    assert attrs(html, "[data-narabe-item]", "data-id") == ["1", "2", "3"]
    assert attrs(html, "[data-narabe-item]", "data-level") == ["1", "2", "1"]
    assert attrs(html, "[data-narabe-item]", "aria-level") == ["1", "2", "1"]
    assert attrs(html, "[data-narabe-item]", "aria-setsize") == ["2", "1", "2"]
    assert attrs(html, "[data-narabe-item][data-parent]", "data-parent") == ["1"]
    assert attrs(html, "[data-children]", "data-id") == ["1"]
    assert attrs(html, "[data-expanded]", "data-id") == ["1"]
    assert attrs(html, "[phx-hook=Narabe]", "data-filter") == ["true"]
    c = config(html)
    assert c["kind"] == "tree"
    assert c["rules"]["nest"] == true
    assert c["onRename"] == "rename"
  end

  test "a tree of several tables: ids that say their kind, the kinds for the rules" do
    tree =
      Mixed.new(
        [
          folder: [from: NarabeTest.Folder, parent: :parent_id],
          document: [from: NarabeTest.Document, parent: :folder_id]
        ],
        parents: :folder
      )

    # As Mixed.items/2 gives them.
    items = [
      %{id: "folder:1", parent_id: nil, kind: "folder", record: %{name: "Docs"}},
      %{id: "document:1", parent_id: "folder:1", kind: "document", record: %{name: "Intro"}},
      %{id: "document:2", parent_id: nil, kind: "document", record: %{name: "Notes"}}
    ]

    assigns = %{items: items, rules: tree.rules}

    html =
      rendered_to_string(~H"""
      <.tree id="files" items={@items} item_kind={:kind} item_label={& &1.record.name} rules={@rules} on_move="move" />
      """)

    assert attrs(html, "[data-narabe-item]", "data-id") == [
             "folder:1",
             "document:1",
             "document:2"
           ]

    assert attrs(html, "[data-narabe-item]", "data-kind") == ["folder", "document", "document"]
    assert attrs(html, "[data-narabe-item]", "data-parent") == ["folder:1"]
    assert config(html)["rules"]["leaves"] == ["document"]
  end

  test "a board: columns and their cards" do
    assigns = %{
      columns: [%{id: 1, name: "Todo"}, %{id: 2, name: "Done"}],
      cards: [
        %{id: 10, title: "a", column_id: 2},
        %{id: 11, title: "b", column_id: 1},
        %{id: 12, title: "c", column_id: 2}
      ]
    }

    html =
      rendered_to_string(~H"""
      <.board id="b" columns={@columns} cards={@cards} on_move="move" move_columns>
        <:card :let={card}>{card.title}</:card>
        <:footer><button>Add</button></:footer>
      </.board>
      """)

    assert attrs(html, "[data-narabe-group]", "data-id") == ["1", "2"]
    assert attrs(html, "#b-column-2 [data-narabe-item]", "data-id") == ["10", "12"]
    assert attrs(html, "#b-column-2 [data-narabe-item]", "data-parent") == ["2", "2"]
    assert length(attrs(html, "[data-narabe-group-handle]", "class")) == 2
    assert config(html)["moveColumns"] == true
    assert html =~ "Add"
  end

  test "a tree picker: a field, the chosen item's ancestors open, disabled subtrees" do
    form = to_form(%{"parent_id" => "3"}, as: :page)

    assigns = %{
      form: form,
      items: [
        %{id: 1, name: "A", parent_id: nil},
        %{id: 2, name: "A1", parent_id: 1},
        %{id: 3, name: "A1x", parent_id: 2},
        %{id: 4, name: "B", parent_id: nil},
        %{id: 5, name: "B1", parent_id: 4}
      ]
    }

    html =
      rendered_to_string(~H"""
      <.tree_picker field={@form[:parent_id]} items={@items} disabled={[4]} />
      """)

    assert attrs(html, "input[data-narabe-value]", "name") == ["page[parent_id]"]
    assert attrs(html, "input[data-narabe-value]", "value") == ["3"]
    assert Enum.sort(attrs(html, "[data-expanded]", "data-id")) == ["1", "2"]
    assert attrs(html, "[aria-disabled]", "data-id") == ["4", "5"]
    c = config(html)
    assert c["kind"] == "picker"
    assert c["value"] == "3"
    assert c["phone"] == "drill"
    assert Enum.sort(c["disabled"]) == ["4", "5"]
  end
end
