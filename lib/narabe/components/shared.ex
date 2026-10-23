defmodule Narabe.Components.Shared do
  @moduledoc false
  # The attributes every list, tree and board has.

  defmacro shared_attrs do
    quote do
      attr :id, :string, required: true, doc: "the element's id, and the list's in its events"
      attr :label, :string, default: nil, doc: "the accessible name of the whole"
      attr :on_move, :string, default: nil, doc: "the event of a move; without it, nothing moves"

      attr :on_select, :string,
        default: nil,
        doc: "the event of a change of the selected items: `%{\"v\" => 1, \"ids\" => [...]}`"

      attr :rules, :any,
        default: nil,
        doc:
          "what may go where: `Narabe.Rules`, its options, or a schema with `use Narabe.Ordered`"

      attr :multiple, :boolean,
        default: false,
        doc: "whether several items are selected and moved together"

      attr :handle, :boolean,
        default: false,
        doc: "whether items drag by their handle only (a finger still holds them anywhere)"

      attr :readonly, :boolean, default: false, doc: "no moves, only focus and selection"
      attr :locale, :string, default: "en", doc: "the language of the words (`Narabe.Messages`)"

      attr :messages, :map,
        default: %{},
        doc: "other words, by the keys of `Narabe.Messages.keys/0`"

      attr :item_id, :any, default: :id, doc: "an item's id: a key or a function"

      attr :item_label, :any,
        default: nil,
        doc: "an item's label, for screen readers and the filter: a key or a function"

      attr :item_kind, :any,
        default: nil,
        doc: "an item's kind, for the rules: a key or a function"

      attr :item_locked, :any,
        default: nil,
        doc: "why an item may not move (a string), or nil: a key or a function"

      attr :class, :any, default: nil
      attr :rest, :global, include: ~w(phx-target)
    end
  end
end
