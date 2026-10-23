defmodule Narabe.Components do
  @moduledoc """
  Lists, trees and boards that people reorder: `sortable_list/1`,
  `tree/1`, `board/1`, and `tree_picker/1` to choose a place in a tree.

      import Narabe.Components

      <.sortable_list id="tasks" items={@streams.tasks} on_move="move">
        <:item :let={task}>{task.title}</:item>
      </.sortable_list>

      <.tree id="pages" items={@pages} on_move="move" rules={[nest: true, max_depth: 6]} filter />

      <.board id="sprint" columns={@columns} cards={@cards} on_move="move_card" move_columns>
        <:column :let={column}>{column.name}</:column>
        <:card :let={card}>{card.title}</:card>
      </.board>

      <.tree_picker field={@form[:folder_id]} items={@folders} />

  Items move with a mouse, a finger (a short hold), or the keyboard (Space
  lifts, the arrows move, Space drops); several move together when
  `multiple`. A drop moves them in the page at once and sends `on_move`
  to the LiveView (or to `phx-target`), with the move as `Narabe.Move.parse/2`
  reads it:

      %{"v" => 1, "ids" => ["7"], "parent" => nil, "after" => "3", "before" => "9", "index" => 2}

  Reply `{:reply, %{ok: true}, socket}` to keep it, or `%{error: "..."}`
  to put the items back (`Narabe.Live.reply/1` makes the reply from what
  `Narabe.Ecto.move/4` returned). A refused move tells the person why.

  The items are structs or maps; the component reads their id from `:id`
  and a label for screen readers from `:name`, `:title` or `:label`, or
  from the functions `item_id` and `item_label`. A list's items may be a
  stream.

  The lists need the `Narabe` hook in the LiveSocket and the Narabe CSS
  (see the README).
  """

  use Phoenix.Component

  import Narabe.Components.Shared

  alias Narabe.{Messages, Rules, Tree}

  # Attributes every component has.
  defp common(assigns, kind, rules_default) do
    rules = Rules.new(assigns.rules || rules_default)
    messages = Messages.for_locale(assigns.locale, assigns.messages)

    config = %{
      "v" => 1,
      "id" => assigns.id,
      "kind" => kind,
      "rules" => Rules.to_client(rules),
      "messages" => messages,
      "locale" => assigns.locale,
      "label" => assigns.label,
      "onMove" => assigns[:on_move],
      "onSelect" => assigns[:on_select],
      "onExpand" => assigns[:on_expand],
      "onRename" => assigns[:on_rename],
      "handle" => assigns[:handle] || nil,
      "multiple" => assigns[:multiple] || nil,
      "readonly" => assigns[:readonly] || nil,
      "moveColumns" => assigns[:move_columns] || nil,
      "phone" => assigns[:phone] && to_string(assigns.phone),
      "name" => assigns[:name],
      "value" => assigns[:value],
      "disabled" => assigns[:disabled_ids]
    }

    assign(assigns,
      kind: kind,
      config: JSON.encode!(reject_nils(config)),
      item_id: Tree.getter(assigns.item_id),
      item_label: if(assigns.item_label, do: Tree.getter(assigns.item_label), else: &label/1),
      item_kind: if(assigns.item_kind, do: Tree.getter(assigns.item_kind)),
      item_locked: if(assigns.item_locked, do: Tree.getter(assigns.item_locked)),
      handle_label: messages["dragHandle"]
    )
  end

  defp reject_nils(map), do: map |> Enum.reject(fn {_, v} -> v == nil end) |> Map.new()

  @doc false
  def label(item) do
    Enum.find_value([:name, :title, :label], "", fn key ->
      case item do
        %{^key => value} when is_binary(value) -> value
        _ -> nil
      end
    end)
  end

  # -- A list ----------------------------------------------------------------------

  @doc """
  A list that people reorder: tasks, a playlist, a menu's links.

  `items` is a list or a stream (`@streams.tasks`). With a stream, insert
  and delete as usual; after a move, `Narabe.Live.stream_move/4` puts the
  item in its new place for every other viewer.
  """
  shared_attrs()
  attr :items, :any, required: true, doc: "the items, in their order: a list or a stream"
  slot :item, doc: "an item, given as `:let`; its label by default"
  slot :actions, doc: "buttons a finger swipes into view (a phone), given the item as `:let`"

  def sortable_list(assigns) do
    assigns = common(assigns, "list", nest: false)
    assigns = assign(assigns, :stream, stream?(assigns.items))
    assigns = assign(assigns, :rows, list_rows(assigns))

    ~H"""
    <div
      id={@id}
      class={["narabe narabe-list", @class]}
      phx-hook="Narabe"
      data-config={@config}
      {@rest}
    >
      <div id={"#{@id}-chrome"} class="narabe-chrome" data-narabe-chrome phx-update="ignore"></div>
      <div
        id={"#{@id}-body"}
        class="narabe-body"
        data-narabe-body
        role="listbox"
        aria-label={@label}
        aria-multiselectable={@multiple && "true"}
        phx-update={@stream && "stream"}
      >
        <.row
          :for={{dom_id, item} <- @rows}
          dom_id={dom_id}
          item={item}
          role="option"
          {row_assigns(assigns, item)}
        >
          <:body>{if @item == [], do: @item_label.(item), else: render_slot(@item, item)}</:body>
          <:actions :if={@actions != []}>{render_slot(@actions, item)}</:actions>
        </.row>
      </div>
    </div>
    """
  end

  defp stream?(%Phoenix.LiveView.LiveStream{}), do: true
  defp stream?(_), do: false

  defp list_rows(%{items: items, id: id, item_id: item_id} = assigns) do
    if assigns.stream, do: items, else: Enum.map(items, &{"#{id}-#{item_id.(&1)}", &1})
  end

  defp row_assigns(assigns, item) do
    %{
      id_value: assigns.item_id.(item),
      label: assigns.item_label.(item),
      kind: assigns.item_kind && assigns.item_kind.(item),
      locked: assigns.item_locked && assigns.item_locked.(item),
      handle: assigns.handle,
      handle_label: assigns.handle_label
    }
  end

  # -- A tree ------------------------------------------------------------------------

  @doc """
  A tree that people reorder and nest: pages, folders and files, an
  outline.

  `items` is flat, as the database has it: each with its parent's id
  (`item_parent`, `:parent_id` by default), in their order. The tree shows
  each under its parent (`Narabe.Tree.rows/2`); a deep tree is fine.

  Rows open and close with a click on their arrow, or Left and Right. With
  `on_expand`, an item with children not loaded yet (`item_children`)
  sends `%{"v" => 1, "id" => id}` as it opens: add its children to `items`.

  With `filter`, a box above the tree shows the items that match, and
  their ancestors. With `on_rename`, F2 or a double click on a label
  renames the item in place and sends `%{"v" => 1, "id" => id, "name" => name}`.

  On a phone, a tree shows as a tree, or one level at a time with
  `phone={:drill}`.
  """
  shared_attrs()
  attr :items, :list, required: true, doc: "the items, flat, in their order"
  attr :item_parent, :any, default: :parent_id, doc: "an item's parent's id: a key or a function"

  attr :item_children, :any,
    default: nil,
    doc: "whether an item has children not loaded yet: a key or a function"

  attr :expanded, :list, default: [], doc: "the ids of the items open at first"

  attr :on_expand, :string,
    default: nil,
    doc: "the event of an item opened whose children are not loaded"

  attr :on_rename, :string, default: nil, doc: "the event of a rename; without it, no renaming"
  attr :filter, :boolean, default: false, doc: "whether a box filters the items"

  attr :phone, :atom,
    default: :tree,
    values: [:tree, :drill],
    doc: "how the tree shows on a phone"

  slot :item, doc: "an item's content, given the item as `:let`; its label by default"
  slot :actions, doc: "buttons a finger swipes into view (a phone), given the item as `:let`"

  def tree(assigns) do
    assigns
    |> common("tree", nest: true)
    |> tree_rows()
    |> tree_markup()
  end

  defp tree_rows(assigns) do
    rows =
      Tree.rows(assigns.items,
        id: assigns.item_id,
        parent: assigns.item_parent,
        children: assigns.item_children
      )

    expanded = MapSet.new(assigns.expanded || [], &to_string/1)

    assigns
    |> assign(rows: rows, expanded_set: expanded)
    |> assign_new(:disabled_ids, fn -> [] end)
  end

  defp tree_markup(assigns) do
    ~H"""
    <div
      id={@id}
      class={["narabe narabe-tree", @kind == "picker" && "narabe-picker", @class]}
      phx-hook="Narabe"
      data-config={@config}
      data-filter={@filter && "true"}
      {@rest}
    >
      <div id={"#{@id}-chrome"} class="narabe-chrome" data-narabe-chrome phx-update="ignore"></div>
      <input :if={@kind == "picker"} type="hidden" name={@name} value={@value} data-narabe-value />
      <div
        id={"#{@id}-body"}
        class="narabe-body"
        data-narabe-body
        role="tree"
        aria-label={@label}
        aria-multiselectable={@multiple && "true"}
      >
        <.row
          :for={row <- @rows}
          dom_id={"#{@id}-#{row.id}"}
          item={row.item}
          role="treeitem"
          level={row.level}
          parent={row.parent}
          posinset={row.index + 1}
          setsize={row.count}
          children={row.children}
          expanded={row.children and MapSet.member?(@expanded_set, to_string(row.id))}
          toggle
          disabled={@kind == "picker" and to_string(row.id) in (@disabled_ids || [])}
          {row_assigns(assigns, row.item)}
        >
          <:body>{if @item == [], do: @item_label.(row.item), else: render_slot(@item, row.item)}</:body>
          <:actions :if={@actions != []}>{render_slot(@actions, row.item)}</:actions>
        </.row>
      </div>
    </div>
    """
  end

  # -- A tree picker -------------------------------------------------------------------

  @doc """
  A field of a form that chooses an item of a tree: a folder to move
  files to, a parent page, a category. It posts the item's id, as a
  `<select>` would; `disabled` items are shown and not offered (the item
  being moved, and those under it).

      <.tree_picker field={@form[:parent_id]} items={@pages} disabled={[@page.id]} />

  On a phone it shows one level at a time unless `phone={:tree}`.
  """
  attr :id, :string, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil, doc: "the form's field"
  attr :name, :string, default: nil
  attr :value, :any, default: nil
  attr :label, :string, default: nil
  attr :items, :list, required: true, doc: "the items, flat, in their order"
  attr :item_id, :any, default: :id
  attr :item_label, :any, default: nil
  attr :item_kind, :any, default: nil
  attr :item_parent, :any, default: :parent_id
  attr :item_children, :any, default: nil
  attr :disabled, :list, default: [], doc: "ids that may not be chosen (and the items under them)"

  attr :expanded, :list,
    default: nil,
    doc: "the ids open at first; by default, the chosen item's ancestors"

  attr :on_expand, :string, default: nil
  attr :filter, :boolean, default: true
  attr :phone, :atom, default: :drill, values: [:tree, :drill]
  attr :rules, :any, default: nil
  attr :locale, :string, default: "en"
  attr :messages, :map, default: %{}
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-target)
  slot :item

  def tree_picker(assigns) do
    {id, name, value} =
      case assigns.field do
        %Phoenix.HTML.FormField{} = f ->
          {assigns.id || f.id, assigns.name || f.name, assigns.value || f.value}

        nil ->
          {assigns.id, assigns.name, assigns.value}
      end

    value = if value in [nil, ""], do: nil, else: to_string(value)
    assigns = assign(assigns, id: id, name: name, value: value, item_locked: nil, actions: [])
    assigns = assign(assigns, handle: false, multiple: false, readonly: true, on_rename: nil)

    assigns
    |> common("picker", nest: true)
    |> tree_rows()
    |> picker_state()
    |> tree_markup()
  end

  # The disabled ids, with the items under them; the chosen item's ancestors open.
  defp picker_state(assigns) do
    rows = assigns.rows
    disabled = MapSet.new(assigns.disabled, &to_string/1)

    {disabled_ids, _} =
      Enum.reduce(rows, {[], nil}, fn row, {acc, under} ->
        cond do
          under && row.level > under -> {[to_string(row.id) | acc], under}
          MapSet.member?(disabled, to_string(row.id)) -> {[to_string(row.id) | acc], row.level}
          true -> {acc, nil}
        end
      end)

    expanded =
      if assigns.expanded do
        MapSet.new(assigns.expanded, &to_string/1)
      else
        ancestors_of(rows, assigns.value)
      end

    config =
      assigns.config |> JSON.decode!() |> Map.put("disabled", disabled_ids) |> JSON.encode!()

    assign(assigns, disabled_ids: disabled_ids, expanded_set: expanded, config: config)
  end

  defp ancestors_of(_rows, nil), do: MapSet.new()

  defp ancestors_of(rows, value) do
    parents = Map.new(rows, &{to_string(&1.id), &1.parent})

    Stream.unfold(parents[value], fn
      nil -> nil
      p -> {to_string(p), parents[to_string(p)]}
    end)
    |> Enum.take(length(rows))
    |> MapSet.new()
  end

  # -- A board -------------------------------------------------------------------------

  @doc """
  A board: columns of cards that people move within a column and across
  them, and, with `move_columns`, columns that move too. A kanban, a
  sprint, a pipeline.

  `columns` are in their order; `cards` are flat, each with its column's
  id (`card_column`, `:column_id` by default), in their order. A card's
  move says its new column as `parent`; a column's move has `"columns" => true`.

  Rules about kinds apply with the column's kind as the parent's
  (`column_kind`), so a column may refuse some cards (`accepts`).
  """
  shared_attrs()
  attr :columns, :list, required: true, doc: "the columns, in their order"
  attr :cards, :list, required: true, doc: "the cards, flat, in their order"
  attr :card_column, :any, default: :column_id, doc: "a card's column id: a key or a function"
  attr :column_id, :any, default: :id
  attr :column_label, :any, default: nil
  attr :column_kind, :any, default: nil
  attr :move_columns, :boolean, default: false, doc: "whether the columns move too"
  slot :column, doc: "a column's header, given the column as `:let`; its label by default"
  slot :item, doc: "a card's content, given the card as `:let`; its label by default"
  slot :card, doc: "the same as `item`"
  slot :actions, doc: "buttons a finger swipes into view (a phone), given the card as `:let`"

  slot :footer,
    doc: "the end of each column (an \"Add a card\" button), given the column as `:let`"

  def board(assigns) do
    assigns = assign(assigns, item: assigns.item ++ assigns.card)
    assigns = common(assigns, "board", nest: false)
    card_column = Tree.getter(assigns.card_column)
    column_id = Tree.getter(assigns.column_id)
    column_label = if assigns.column_label, do: Tree.getter(assigns.column_label), else: &label/1
    column_kind = if assigns.column_kind, do: Tree.getter(assigns.column_kind)
    by_column = Enum.group_by(assigns.cards, &to_string(card_column.(&1)))

    columns =
      for column <- assigns.columns do
        id = column_id.(column)

        %{
          item: column,
          id: id,
          label: column_label.(column),
          kind: column_kind && column_kind.(column),
          cards: Map.get(by_column, to_string(id), [])
        }
      end

    assigns = assign(assigns, board_columns: columns)

    ~H"""
    <div
      id={@id}
      class={["narabe narabe-board", @class]}
      phx-hook="Narabe"
      data-config={@config}
      role="group"
      aria-label={@label}
      {@rest}
    >
      <div id={"#{@id}-chrome"} class="narabe-chrome" data-narabe-chrome phx-update="ignore"></div>
      <div id={"#{@id}-body"} class="narabe-body narabe-columns" data-narabe-body>
        <section
          :for={column <- @board_columns}
          id={"#{@id}-column-#{column.id}"}
          class="narabe-column"
          data-narabe-group
          data-id={column.id}
          data-kind={column.kind}
          data-label={column.label}
          aria-labelledby={"#{@id}-column-#{column.id}-title"}
        >
          <header class="narabe-column-header">
            <span
              :if={@move_columns}
              class="narabe-handle narabe-column-handle"
              data-narabe-group-handle
              role="button"
              tabindex="-1"
              aria-label={"#{@handle_label}: #{column.label}"}
            ></span>
            <h3 id={"#{@id}-column-#{column.id}-title"} class="narabe-column-title">
              {if @column == [], do: column.label, else: render_slot(@column, column.item)}
            </h3>
            <span class="narabe-column-count">{length(column.cards)}</span>
          </header>
          <div
            id={"#{@id}-column-#{column.id}-body"}
            class="narabe-column-body"
            data-narabe-group-body
            role="listbox"
            aria-labelledby={"#{@id}-column-#{column.id}-title"}
            aria-multiselectable={@multiple && "true"}
          >
            <.row
              :for={card <- column.cards}
              dom_id={"#{@id}-#{@item_id.(card)}"}
              item={card}
              role="option"
              parent={column.id}
              {row_assigns(assigns, card)}
            >
              <:body>{if @item == [], do: @item_label.(card), else: render_slot(@item, card)}</:body>
              <:actions :if={@actions != []}>{render_slot(@actions, card)}</:actions>
            </.row>
          </div>
          <footer :if={@footer != []} class="narabe-column-footer">{render_slot(@footer, column.item)}</footer>
        </section>
      </div>
    </div>
    """
  end

  # -- A row ------------------------------------------------------------------------------

  attr :dom_id, :string, required: true
  attr :item, :any, required: true
  attr :id_value, :any, required: true
  attr :label, :string, required: true
  attr :kind, :string, default: nil
  attr :locked, :string, default: nil
  attr :role, :string, required: true
  attr :level, :integer, default: 1
  attr :parent, :any, default: nil
  attr :posinset, :integer, default: nil
  attr :setsize, :integer, default: nil
  attr :children, :boolean, default: false
  attr :expanded, :boolean, default: false
  attr :toggle, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :handle, :boolean, default: false
  attr :handle_label, :string, default: nil
  slot :body, required: true
  slot :actions

  defp row(assigns) do
    ~H"""
    <div
      id={@dom_id}
      class={["narabe-item", @locked && "narabe-locked"]}
      data-narabe-item
      data-id={@id_value}
      data-kind={@kind}
      data-level={@level}
      data-parent={@parent}
      data-children={@children && "true"}
      data-expanded={@expanded && "true"}
      data-label={@label}
      data-locked={@locked}
      role={@role}
      aria-level={@role == "treeitem" && @level}
      aria-posinset={@posinset}
      aria-setsize={@setsize}
      aria-disabled={@disabled && "true"}
      tabindex="-1"
      style={"--narabe-level: #{@level}"}
    >
      <div class="narabe-content" data-narabe-content>
        <span :if={@toggle} class="narabe-toggle" data-narabe-toggle aria-hidden="true"></span>
        <span :if={@handle} class="narabe-handle" data-narabe-handle aria-hidden="true" title={@handle_label}></span>
        <span class="narabe-label" data-narabe-label>{render_slot(@body)}</span>
      </div>
      <div :if={@actions != []} class="narabe-actions" data-narabe-actions>{render_slot(@actions)}</div>
    </div>
    """
  end
end
