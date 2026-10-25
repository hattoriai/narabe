defmodule Narabe.EctoMixedCases do
  @moduledoc false
  # Narabe.Ecto.Mixed's tests, once for each database: a tree of folders
  # (in folders) and documents (in folders), two tables.

  defmacro __using__(repo: repo) do
    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote do
      import Ecto.Query

      alias Ecto.Adapters.SQL.Sandbox
      alias Narabe.Ecto.Mixed
      alias Narabe.Move
      alias NarabeTest.{Document, Folder}
      alias unquote(repo), as: Repo

      # docs
      #   guides
      #     intro (document)
      #   readme (document)
      #   api
      # notes (document)
      setup do
        :ok = Sandbox.checkout(Repo)
        tree = tree()
        docs = folder(tree, "docs", nil)
        guides = folder(tree, "guides", docs)
        document(tree, "intro", guides)
        document(tree, "readme", docs)
        folder(tree, "api", docs)
        document(tree, "notes", nil)
        %{tree: tree}
      end

      defp tree(opts \\ []) do
        Mixed.new(
          [
            folder: [from: Folder, parent: :parent_id],
            document: [from: Document, parent: :folder_id]
          ],
          Keyword.merge([parents: :folder], opts)
        )
      end

      defp folder(tree, name, parent) do
        at = parent && Mixed.id(:folder, parent.id)

        Repo.insert!(%Folder{
          name: name,
          parent_id: parent && parent.id,
          position: Mixed.insert_position(Repo, tree, :last, in: at)
        })
      end

      defp document(tree, title, parent) do
        %Document{}
        |> Document.changeset(%{title: title, folder_id: parent && parent.id})
        |> Mixed.put_position(Repo, tree)
        |> Repo.insert!()
      end

      defp ref(name) do
        case Repo.one(from(f in Folder, where: f.name == ^name, select: f.id)) do
          nil ->
            Mixed.id(
              :document,
              Repo.one!(from(d in Document, where: d.title == ^name, select: d.id))
            )

          id ->
            Mixed.id(:folder, id)
        end
      end

      # The names of a folder's children (nil: the top level), in order.
      defp children(tree, name) do
        parent = name && ref(name)

        for item <- Mixed.items(Repo, tree), item.parent_id == parent do
          Map.get(item.record, :name) || item.record.title
        end
      end

      defp move(tree, name, opts) do
        Mixed.move(Repo, tree, %Move{
          ids: Enum.map(List.wrap(name), &ref/1),
          parent: opts[:to] && ref(opts[:to]),
          after: opts[:after] && ref(opts[:after]),
          before: opts[:before] && ref(opts[:before]),
          index: opts[:index]
        })
      end

      test "the items: each table's rows, one order among siblings, ids that say their kind", %{
        tree: tree
      } do
        assert children(tree, nil) == ~w(docs notes)
        assert children(tree, "docs") == ~w(guides readme api)

        intro =
          Enum.find(
            Mixed.items(Repo, tree),
            &(&1.kind == "document" and &1.record.title == "intro")
          )

        assert intro.id == ref("intro")
        assert intro.parent_id == ref("guides")
        assert "document:" <> _ = intro.id
      end

      test "a document moves between folders, among folders and documents", %{tree: tree} do
        assert {:ok, [%Document{title: "notes"}]} =
                 move(tree, "notes", to: "docs", after: "guides")

        assert children(tree, "docs") == ~w(guides notes readme api)
        assert children(tree, nil) == ~w(docs)

        assert {:ok, _} = move(tree, "intro", to: "docs", before: "api")
        assert children(tree, "docs") == ~w(guides notes readme intro api)
        assert children(tree, "guides") == []

        assert {:ok, _} = move(tree, "readme", to: "docs", index: 0)
        assert children(tree, "docs") == ~w(readme guides notes intro api)

        assert {:ok, _} = move(tree, "readme", to: nil)
        assert children(tree, nil) == ~w(docs readme)
      end

      test "a folder moves with its folders and documents", %{tree: tree} do
        assert {:ok, [%Folder{name: "guides"}]} = move(tree, "guides", to: "api")
        assert children(tree, "api") == ~w(guides)
        assert children(tree, "guides") == ~w(intro)
      end

      test "several items of both kinds move together, in their order", %{tree: tree} do
        assert {:ok, rows} = move(tree, ["readme", "api"], to: nil, after: "docs")
        assert Enum.map(rows, &(Map.get(&1, :name) || &1.title)) == ~w(readme api)
        assert children(tree, nil) == ~w(docs readme api notes)
      end

      test "a move writes only the moved row", %{tree: tree} do
        keys = fn ->
          Map.new(Repo.all(from(f in Folder, select: {f.name, f.position})))
          |> Map.merge(Map.new(Repo.all(from(d in Document, select: {d.title, d.position}))))
        end

        before = keys.()
        {:ok, _} = move(tree, "api", to: "docs", after: "guides")
        assert Map.delete(before, "api") == Map.delete(keys.(), "api")
      end

      test "never into itself or under itself", %{tree: tree} do
        assert {:error, :into_itself} = move(tree, "docs", to: "guides")
        assert {:error, :into_itself} = move(tree, "docs", to: "docs")
        assert children(tree, nil) == ~w(docs notes)
      end

      test "only a parent's kind holds others", %{tree: tree} do
        assert {:error, :not_accepted} = move(tree, "api", to: "readme")
        assert "document" in tree.rules.leaves
      end

      test "the deepest level counts the levels of both kinds under the moved items" do
        tree = tree(rules: [max_depth: 3])

        # guides holds intro: under api (depth 2) intro would be at 4.
        assert {:error, :too_deep} = move(tree, "guides", to: "api")
        assert {:ok, _} = move(tree, "api", to: "guides")
        # api is now at depth 3: a document under it would be at 4.
        assert {:error, :too_deep} = move(tree, "notes", to: "api")
      end

      test "the rules' accepts, by kind" do
        tree = tree(rules: [accepts: %{"root" => ["folder"]}])
        assert {:error, :not_accepted} = move(tree, "readme", to: nil)
        assert {:ok, _} = move(tree, "api", to: nil)
      end

      test "an item or a parent that is not of the tree, or not in its queryable, is not found",
           %{tree: tree} do
        assert {:error, :not_found} = Mixed.move(Repo, tree, %Move{ids: ["page:1"]})
        assert {:error, :not_found} = Mixed.move(Repo, tree, %Move{ids: ["document:999999"]})

        assert {:error, :not_found} =
                 Mixed.move(Repo, tree, %Move{ids: [ref("notes")], parent: "folder:999999"})

        docs_id = Repo.one!(from(f in Folder, where: f.name == "docs", select: f.id))

        scoped =
          Mixed.new(
            [
              folder: [from: where(Folder, [f], f.id != ^docs_id), parent: :parent_id],
              document: [from: Document, parent: :folder_id]
            ],
            parents: :folder
          )

        assert {:error, :not_found} = move(scoped, "notes", to: "docs")
      end

      test "a refused move stops the whole Multi", %{tree: tree} do
        multi =
          Ecto.Multi.new()
          |> Ecto.Multi.run(:first, fn repo, _ ->
            {:ok, repo.update_all(Document, set: [title: "changed"])}
          end)
          |> Mixed.move_multi(:move, tree, %Move{ids: [ref("docs")], parent: ref("guides")})

        assert {:error, :move, :into_itself, _} = Repo.transaction(multi)
        refute Repo.exists?(from(d in Document, where: d.title == "changed"))
      end

      test "positions for new rows: first, last, after and before a sibling of either kind", %{
        tree: tree
      } do
        docs = ref("docs")

        first = Mixed.insert_position(Repo, tree, :first, in: docs)
        last = Mixed.insert_position(Repo, tree, :last, in: docs)
        between = Mixed.insert_position(Repo, tree, {:after, ref("guides")}, in: docs)
        before_api = Mixed.insert_position(Repo, tree, {:before, ref("api")}, in: docs)

        keys =
          for item <- Mixed.items(Repo, tree), item.parent_id == docs, do: item.record.position

        assert first < hd(keys)
        assert last > List.last(keys)
        assert Enum.at(keys, 0) < between and between < Enum.at(keys, 1)
        assert Enum.at(keys, 1) < before_api and before_api < Enum.at(keys, 2)
      end

      test "rows without keys get keys in their order as a move first touches their parent", %{
        tree: tree
      } do
        Repo.update_all(Document, set: [position: nil])
        Repo.update_all(Folder, set: [position: nil])

        assert {:ok, _} = move(tree, "notes", to: "docs", after: "readme")
        assert List.last(children(tree, "docs")) in ~w(notes api)

        refute Repo.exists?(
                 from(f in Folder,
                   where:
                     f.parent_id ==
                       ^Repo.one!(from(f in Folder, where: f.name == "docs", select: f.id)) and
                       is_nil(f.position)
                 )
               )
      end

      test "landing in one gap again and again keeps the order and rebalances long keys" do
        tree = tree(rebalance_at: 6)

        for _ <- 1..12 do
          [first, second | _] = children(tree, "docs")
          {:ok, _} = move(tree, List.last(children(tree, "docs")), to: "docs", after: first)
          assert Enum.at(children(tree, "docs"), 2) == second
        end

        keys = for item <- Mixed.items(Repo, tree), do: item.record.position
        assert Enum.all?(keys, &(byte_size(&1) <= 7))
      end

      test "rebalance writes a parent's children's keys evenly, in order", %{tree: tree} do
        order = children(tree, "docs")
        assert Mixed.rebalance(Repo, tree, in: ref("docs")) == 3
        assert children(tree, "docs") == order
      end

      test "ids read back by kind, and raise for what is not a parent", %{tree: tree} do
        assert {:ok, {"folder", id}} = Mixed.parse_id(tree, ref("docs"))
        assert is_integer(id)
        assert Mixed.parse_id(tree, "page:1") == :error
        assert Mixed.parse_id(tree, "folder:x") == :error
        assert Mixed.parse_id(tree, "folder") == :error

        assert_raise ArgumentError, fn ->
          Mixed.insert_position(Repo, tree, :last, in: ref("notes"))
        end

        assert Mixed.id_of(tree, Repo.get_by!(Document, title: "notes")) == ref("notes")
      end

      test "a move's params from the browser, ids as text" do
        tree = tree()
        params = Move.to_params(%Move{ids: [ref("notes")], parent: ref("api")})
        assert {:ok, _} = Mixed.move(Repo, tree, Move.parse!(params))
        assert children(tree, "api") == ~w(notes)
      end
    end
  end
end

defmodule Narabe.EctoMixedTest do
  use ExUnit.Case, async: true

  alias Narabe.Ecto.Mixed

  test "a tree needs its parents' kind among its kinds" do
    assert_raise ArgumentError, ~r/not a kind/, fn ->
      Mixed.new([document: [from: NarabeTest.Document, parent: :folder_id]], parents: :folder)
    end
  end

  test "the kinds other than the parents' hold nothing, and the tree nests" do
    tree =
      Mixed.new(
        [
          folder: [from: NarabeTest.Folder, parent: :parent_id],
          document: [from: NarabeTest.Document, parent: :folder_id]
        ],
        parents: :folder,
        rules: [max_depth: 4, leaves: ["file"]]
      )

    assert %Narabe.Rules{nest: true, max_depth: 4, leaves: ["file", "document"]} = tree.rules
    doctest_id = Mixed.id(:folder, 3)
    assert doctest_id == "folder:3"
  end

  doctest Narabe.Ecto.Mixed
end

defmodule Narabe.EctoMixedTest.Postgres do
  use ExUnit.Case, async: true
  @moduletag db: "postgres"
  use Narabe.EctoMixedCases, repo: NarabeTest.Repo
end

defmodule Narabe.EctoMixedTest.MySQL do
  use ExUnit.Case, async: true
  @moduletag db: "mysql"
  use Narabe.EctoMixedCases, repo: NarabeTest.MyRepo
end

defmodule Narabe.EctoMixedTest.SQLite do
  # SQLite writes one transaction at a time.
  use ExUnit.Case, async: false
  @moduletag db: "sqlite"
  use Narabe.EctoMixedCases, repo: NarabeTest.LiteRepo
end
