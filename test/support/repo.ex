defmodule NarabeTest.Repo do
  @moduledoc "The Postgres repo of Narabe.Ecto's tests."
  use Ecto.Repo, otp_app: :narabe, adapter: Ecto.Adapters.Postgres
end

defmodule NarabeTest.MyRepo do
  @moduledoc "The MySQL repo of Narabe.Ecto's tests."
  use Ecto.Repo, otp_app: :narabe, adapter: Ecto.Adapters.MyXQL
end

defmodule NarabeTest.LiteRepo do
  @moduledoc "The SQLite repo of Narabe.Ecto's tests."
  use Ecto.Repo, otp_app: :narabe, adapter: Ecto.Adapters.SQLite3
end

defmodule NarabeTest.Databases do
  @moduledoc "The databases of the tests: those NARABE_DBS names, each created afresh and migrated."

  alias Ecto.Adapters.SQL.Sandbox

  @repos %{
    "postgres" => NarabeTest.Repo,
    "mysql" => NarabeTest.MyRepo,
    "sqlite" => NarabeTest.LiteRepo
  }

  def wanted,
    do:
      System.get_env("NARABE_DBS", "postgres,mysql,sqlite")
      |> String.split(",", trim: true)
      |> Enum.filter(&Map.has_key?(@repos, &1))

  def start do
    for name <- wanted() do
      repo = Map.fetch!(@repos, name)
      config = repo.config()
      adapter = repo.__adapter__()
      _ = adapter.storage_down(config)
      :ok = adapter.storage_up(config)
      {:ok, _pid} = repo.start_link()
      Ecto.Migrator.up(repo, 1, NarabeTest.Migration, log: false)
      Sandbox.mode(repo, :manual)
      name
    end
  end
end

defmodule NarabeTest.Migration do
  @moduledoc "The tables of the tests: a board's cards, and a tree's pages."
  use Ecto.Migration

  import Narabe.Migration

  def change do
    create table(:columns) do
      add(:name, :string)
      position(:position)
    end

    create table(:cards) do
      add(:title, :string)
      add(:column_id, references(:columns))
      position(:position)
    end

    create(index(:cards, [:column_id, :position]))

    create table(:pages) do
      add(:title, :string)
      add(:kind, :string, default: "page")
      add(:parent_id, references(:pages))
      position(:position)
    end

    create(index(:pages, [:parent_id, :position]))
  end
end

defmodule NarabeTest.Column do
  @moduledoc false
  use Ecto.Schema

  schema "columns" do
    field(:name, :string)
    field(:position, :string)
    has_many(:cards, NarabeTest.Card)
  end
end

defmodule NarabeTest.Card do
  @moduledoc false
  use Ecto.Schema

  schema "cards" do
    field(:title, :string)
    field(:position, :string)
    belongs_to(:column, NarabeTest.Column)
  end

  use Narabe.Ordered, group: :column_id

  def changeset(card, attrs), do: Ecto.Changeset.cast(card, attrs, [:title, :column_id])
end

defmodule NarabeTest.Page do
  @moduledoc false
  use Ecto.Schema

  schema "pages" do
    field(:title, :string)
    field(:kind, :string, default: "page")
    field(:position, :string)
    belongs_to(:parent, NarabeTest.Page)
  end

  use Narabe.Ordered, group: :parent_id, tree: true, kind: :kind
end
