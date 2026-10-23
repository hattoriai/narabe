defmodule Narabe.EctoCases do
  @moduledoc false
  # Narabe.Ecto's tests, once for each database (Postgres, MySQL, SQLite):
  # a board's cards, a tree's pages (test/support/repo.ex).

  defmacro __using__(repo: repo) do
    quote do
      import Ecto.Query

      alias Narabe.Move
      alias NarabeTest.{Card, Column, Page}
      alias unquote(repo), as: Repo

      setup do
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      end

      defp column(name) do
        Repo.insert!(%Column{name: name, position: Narabe.Ecto.insert_position(Repo, Column)})
      end

      defp card(column, title, at \\ :last) do
        position = Narabe.Ecto.insert_position(Repo, where(Card, column_id: ^column.id), at)
        Repo.insert!(%Card{title: title, column_id: column.id, position: position})
      end

      defp titles(column) do
        Card
        |> where(column_id: ^column.id)
        |> Narabe.Ecto.ordered()
        |> select([c], c.title)
        |> Repo.all()
      end

      defp id(title), do: Repo.one!(from(c in Card, where: c.title == ^title, select: c.id))

      defp move(title, opts) do
        move = %Move{
          ids: [id(title)],
          parent: opts[:to],
          after: opts[:after] && id(opts[:after]),
          before: opts[:before] && id(opts[:before]),
          index: opts[:index]
        }

        Narabe.Ecto.move(Repo, Card, move, group: :column_id)
      end

      describe "a list" do
        setup do
          todo = column("To do")
          for title <- ~w(a b c d e), do: card(todo, title)
          %{todo: todo}
        end

        test "after an item, before an item, at an index, at the end", %{todo: todo} do
          assert {:ok, [%Card{title: "a"}]} = move("a", to: todo.id, after: "c")
          assert titles(todo) == ~w(b c a d e)

          assert {:ok, _} = move("e", to: todo.id, before: "b")
          assert titles(todo) == ~w(e b c a d)

          assert {:ok, _} = move("b", to: todo.id, index: 0)
          assert titles(todo) == ~w(b e c a d)

          assert {:ok, _} = move("c", to: todo.id)
          assert titles(todo) == ~w(b e a d c)
        end

        test "a move writes only the moved row", %{todo: todo} do
          before =
            Card
            |> where(column_id: ^todo.id)
            |> select([c], {c.title, c.position})
            |> Repo.all()
            |> Map.new()

          {:ok, _} = move("e", to: todo.id, after: "a")

          now =
            Card
            |> where(column_id: ^todo.id)
            |> select([c], {c.title, c.position})
            |> Repo.all()
            |> Map.new()

          assert Map.delete(before, "e") == Map.delete(now, "e")
        end

        test "after: a neighbour that is gone falls back to before, then the index", %{todo: todo} do
          gone = id("b")
          Repo.delete_all(where(Card, id: ^gone))
          move = %Move{ids: [id("e")], parent: todo.id, after: gone, before: id("c")}
          assert {:ok, _} = Narabe.Ecto.move(Repo, Card, move, group: :column_id)
          assert titles(todo) == ~w(a e c d)
        end

        test "landing in one gap again and again keeps the order, and rebalances long keys", %{
          todo: todo
        } do
          for i <- 1..60 do
            card(todo, "n#{i}", {:after, id("a")})
          end

          keys =
            Card
            |> where(column_id: ^todo.id)
            |> Narabe.Ecto.ordered()
            |> select([c], c.position)
            |> Repo.all()

          assert keys == Enum.sort(keys)

          {:ok, _} = move("e", to: todo.id, after: "a")

          long =
            Card
            |> where(column_id: ^todo.id)
            |> select([c], max(fragment("length(?)", c.position)))
            |> Repo.one()

          assert long <= 32
          assert hd(titles(todo)) == "a"
          assert Enum.at(titles(todo), 1) == "e"
        end
      end

      describe "a board" do
        test "a card moves to another column, between two cards" do
          todo = column("To do")
          done = column("Done")
          for title <- ~w(a b), do: card(todo, title)
          for title <- ~w(x y), do: card(done, title)

          assert {:ok, [%Card{column_id: done_id}]} = move("a", to: done.id, after: "x")
          assert done_id == done.id
          assert titles(todo) == ~w(b)
          assert titles(done) == ~w(x a y)
        end

        test "several cards at once keep their order" do
          todo = column("To do")
          done = column("Done")
          for title <- ~w(a b c), do: card(todo, title)
          card(done, "x")

          move = %Move{ids: [id("c"), id("a")], parent: done.id, before: id("x")}
          assert {:ok, moved} = Narabe.Ecto.move(Repo, Card, move, group: :column_id)
          assert Enum.map(moved, & &1.title) == ~w(c a)
          assert titles(done) == ~w(c a x)
        end

        test "a card outside the queryable is not found, and nothing changes" do
          todo = column("To do")
          card(todo, "a")
          other = Repo.insert!(%Card{title: "elsewhere", position: "a0"})
          move = %Move{ids: [id("a"), other.id], parent: todo.id}

          assert {:error, :not_found} =
                   Narabe.Ecto.move(Repo, where(Card, column_id: ^todo.id), move,
                     group: :column_id
                   )
        end

        test "the rules: a column takes only cards" do
          todo = column("To do")
          card(todo, "a")
          move = %Move{ids: [id("a")], parent: todo.id}

          assert {:error, :not_accepted} =
                   Narabe.Ecto.move(Repo, Card, move,
                     group: :column_id,
                     group_kind: "column",
                     rules: [accepts: %{"column" => ["card"]}]
                   )
        end

        test "rows without keys are given keys in their order as a move first touches them" do
          todo = column("To do")
          for title <- ~w(a b c), do: Repo.insert!(%Card{title: title, column_id: todo.id})
          assert {:ok, _} = move("a", to: todo.id, after: "b")
          assert titles(todo) == ~w(b a c)
          refute Repo.exists?(from(c in Card, where: is_nil(c.position)))
        end
      end

      describe "a tree" do
        # root
        #   product
        #     roadmap
        #     specs
        #       narabe
        #   design
        setup do
          root = page("root", nil)
          product = page("product", root)
          page("roadmap", product)
          specs = page("specs", product)
          page("narabe", specs)
          page("design", root)
          :ok
        end

        defp page(title, parent) do
          parent_id = parent && parent.id

          scope =
            if parent_id,
              do: where(Page, parent_id: ^parent_id),
              else: where(Page, [p], is_nil(p.parent_id))

          Repo.insert!(%Page{
            title: title,
            parent_id: parent_id,
            position: Narabe.Ecto.insert_position(Repo, scope)
          })
        end

        defp pid(title), do: Repo.one!(from(p in Page, where: p.title == ^title, select: p.id))

        defp children(title) do
          Page
          |> where(parent_id: ^pid(title))
          |> Narabe.Ecto.ordered()
          |> select([p], p.title)
          |> Repo.all()
        end

        defp move_page(title, to, opts \\ []) do
          move = %Move{
            ids: [pid(title)],
            parent: to && pid(to),
            after: opts[:after] && pid(opts[:after])
          }

          Narabe.Ecto.move(
            Repo,
            Page,
            move,
            Keyword.merge([group: :parent_id, tree: true], opts[:with] || [])
          )
        end

        test "an item moves to another parent, its children with it" do
          assert {:ok, _} = move_page("specs", "design")
          assert children("design") == ~w(specs)
          assert children("specs") == ~w(narabe)
          assert children("product") == ~w(roadmap)
        end

        test "to the top level" do
          assert {:ok, [%Page{parent_id: nil}]} = move_page("narabe", nil, after: "root")
        end

        test "never into itself or its descendants" do
          assert {:error, :into_itself} = move_page("product", "narabe")
          assert {:error, :into_itself} = move_page("specs", "narabe")
          assert children("product") == ~w(roadmap specs)
        end

        test "the deepest level counts the moved item's children" do
          # specs has one level under it: under narabe (depth 4) it would reach 6.
          assert {:error, :too_deep} =
                   move_page("specs", "design", with: [rules: [nest: true, max_depth: 3]])

          assert {:ok, _} =
                   move_page("roadmap", "narabe", with: [rules: [nest: true, max_depth: 5]])

          # roadmap is now at depth 5 (root, product, specs, narabe, roadmap).
          assert {:error, :too_deep} =
                   move_page("design", "roadmap", with: [rules: [nest: true, max_depth: 5]])
        end

        test "kinds: a file holds nothing" do
          Repo.update_all(where(Page, title: "roadmap"), set: [kind: "file"])

          assert {:error, :not_accepted} =
                   move_page("design", "roadmap",
                     with: [kind: :kind, rules: [nest: true, leaves: ["file"]]]
                   )
        end

        test "ancestors, the parent first" do
          assert Narabe.Ecto.ancestors(Repo, Page, pid("narabe"), group: :parent_id) ==
                   [pid("specs"), pid("product"), pid("root")]
        end
      end

      describe "the schema's order (Narabe.Ordered), Ecto.Multi, changesets" do
        test "a move takes the schema's options, and composes in a Multi" do
          todo = column("To do")
          done = column("Done")
          card(todo, "a")
          card(done, "x")

          result =
            Ecto.Multi.new()
            |> Narabe.Ecto.move_multi(:move, Card, %Move{
              ids: [id("a")],
              parent: done.id,
              after: id("x")
            })
            |> Ecto.Multi.run(:count, fn repo, %{move: [card]} ->
              {:ok, repo.aggregate(where(Card, column_id: ^card.column_id), :count)}
            end)
            |> Repo.transaction()

          assert {:ok, %{move: [%Card{title: "a"}], count: 2}} = result
          assert titles(done) == ~w(x a)
        end

        test "a refused move stops the whole Multi" do
          todo = column("To do")
          card(todo, "a")

          result =
            Ecto.Multi.new()
            |> Ecto.Multi.insert(:other, %Column{name: "Should not stay", position: "b0"})
            |> Narabe.Ecto.move_multi(:move, Card, %Move{ids: [-1], parent: todo.id})
            |> Repo.transaction()

          assert {:error, :move, :not_found, _} = result
          refute Repo.exists?(where(Column, name: "Should not stay"))
        end

        test "a changeset gets its position at the end of its column" do
          todo = column("To do")
          card(todo, "a")

          new =
            %Card{}
            |> Card.changeset(%{title: "b", column_id: todo.id})
            |> Narabe.Ecto.put_position(Repo)
            |> Repo.insert!()

          assert new.position > Repo.get_by!(Card, title: "a").position
          assert titles(todo) == ~w(a b)

          first =
            %Card{}
            |> Card.changeset(%{title: "z", column_id: todo.id})
            |> Narabe.Ecto.put_position(Repo, :first)
            |> Repo.insert!()

          assert first.position < Repo.get_by!(Card, title: "a").position
        end

        test "serialize locks the list's owner first, and the move still lands" do
          todo = column("To do")
          for title <- ~w(a b c), do: card(todo, title)

          assert {:ok, _} =
                   Narabe.Ecto.move(Repo, Card, %Move{ids: [id("c")], parent: todo.id, index: 0},
                     serialize: where(Column, id: ^todo.id)
                   )

          assert titles(todo) == ~w(c a b)
        end
      end

      test "a deep tree: 500 levels, read with one recursive query each way" do
        top = Repo.insert!(%Page{title: "level 0", position: "a0"})

        bottom =
          Enum.reduce(1..499, top, fn level, parent ->
            Repo.insert!(%Page{title: "level #{level}", parent_id: parent.id, position: "a0"})
          end)

        assert length(Narabe.Ecto.ancestors(Repo, Page, bottom.id)) == 499
        assert length(Narabe.Ecto.descendants(Repo, Page, top.id)) == 499

        # The top cannot go under the bottom; the bottom may go to the top level.
        assert {:error, :into_itself} =
                 Narabe.Ecto.move(Repo, Page, %Move{ids: [top.id], parent: bottom.id})

        assert {:error, :too_deep} =
                 Narabe.Ecto.move(Repo, Page, %Move{ids: [top.id], parent: nil},
                   rules: [nest: true, max_depth: 100]
                 )

        assert {:ok, [%Page{parent_id: nil}]} =
                 Narabe.Ecto.move(Repo, Page, %Move{ids: [bottom.id], parent: nil})
      end

      test "rebalance writes a scope's keys evenly, in order" do
        todo = column("To do")
        for title <- ~w(a b c), do: card(todo, title)
        for _ <- 1..30, do: card(todo, "z", {:after, id("a")})
        assert Narabe.Ecto.rebalance(Repo, where(Card, column_id: ^todo.id)) == 33

        keys =
          Card
          |> where(column_id: ^todo.id)
          |> Narabe.Ecto.ordered()
          |> select([c], c.position)
          |> Repo.all()

        assert Enum.all?(keys, &(byte_size(&1) <= 3))
        assert List.first(titles(todo)) == "a"
        assert List.last(titles(todo)) == "c"
      end

      test "the column compares bytes (COLLATE \"C\"): B sorts before a" do
        todo = column("To do")
        Repo.insert!(%Card{title: "lower", column_id: todo.id, position: "a0"})
        Repo.insert!(%Card{title: "upper", column_id: todo.id, position: "B0"})
        assert titles(todo) == ~w(upper lower)
      end
    end
  end
end

defmodule Narabe.EctoTest.Postgres do
  use ExUnit.Case, async: true
  @moduletag db: "postgres"
  use Narabe.EctoCases, repo: NarabeTest.Repo
end

defmodule Narabe.EctoTest.MySQL do
  use ExUnit.Case, async: true
  @moduletag db: "mysql"
  use Narabe.EctoCases, repo: NarabeTest.MyRepo
end

defmodule Narabe.EctoTest.SQLite do
  # SQLite writes one transaction at a time.
  use ExUnit.Case, async: false
  @moduletag db: "sqlite"
  use Narabe.EctoCases, repo: NarabeTest.LiteRepo
end
