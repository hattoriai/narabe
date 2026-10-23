if Code.ensure_loaded?(Ecto.Migration) do
  defmodule Narabe.Migration do
    @moduledoc """
    The column of an item's position, in a migration: a text compared byte
    by byte, as position keys must be (see `Narabe.Position`).

        defmodule MyApp.Repo.Migrations.CreateCards do
          use Ecto.Migration
          import Narabe.Migration

          def change do
            create table(:cards) do
              add :title, :string
              add :column_id, references(:columns)
              position()
            end

            create index(:cards, [:column_id, :position])
          end
        end

    The column is `:string`, not null when you say so (`null: false`), with
    the collation that compares bytes: `"C"` on Postgres, `utf8mb4_bin` on
    MySQL; SQLite compares bytes already. For a column that already exists,
    `alter_position/2` changes its collation.

    Index the position after the item's scope (its list, column or parent):
    a list is read in its order with that index.
    """

    import Ecto.Migration

    @doc """
    Adds a position column (`:position` unless named), in a `create table`
    or `alter table`. Options go to `Ecto.Migration.add/3` (`null: false`).
    """
    @spec position(atom(), keyword()) :: :ok
    def position(name \\ :position, opts \\ []) do
      add(name, :string, Keyword.merge(collation(), opts))
      :ok
    end

    @doc """
    Makes an existing column compare bytes, in an `alter table`: for a
    position column added before Narabe.
    """
    @spec alter_position(atom(), keyword()) :: :ok
    def alter_position(name \\ :position, opts \\ []) do
      modify(name, :string, Keyword.merge(collation(), opts))
      :ok
    end

    # The collation that compares bytes, for the repo's database.
    defp collation do
      case repo().__adapter__() |> Module.split() |> List.last() do
        "Postgres" -> [collation: "C"]
        "MyXQL" -> [collation: "utf8mb4_bin"]
        _other -> []
      end
    end
  end
end
