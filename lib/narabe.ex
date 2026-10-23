defmodule Narabe do
  @moduledoc """
  Lists, trees and boards that people reorder, for Phoenix LiveView: the
  components in `Narabe.Components` (`sortable_list/1`, `tree/1`,
  `board/1`, `tree_picker/1`), and the order in your database with
  `Narabe.Ecto`.

  Items move with a mouse, a finger or the keyboard. A move says where by
  ids (`Narabe.Move`), not by an index; the browser moves the items at
  once and the LiveView applies the move, in one transaction that writes
  the moved rows only (`Narabe.Ecto`, on Postgres, MySQL and SQLite), or
  in memory (`Narabe.Move.apply/3`). What may go where (`Narabe.Rules`)
  holds in the browser, as people drag, and on the server.

  With [Issho](https://hex.pm/packages/issho), people see each other drag,
  and agents move items as people watch (`Narabe.Issho`).
  """
end
