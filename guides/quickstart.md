# Quickstart

A to-do list that people reorder with a mouse, a finger or the keyboard,
with the order saved in the database.

## 1. Install

Narabe needs Elixir 1.18 or later, Phoenix 1.7.14 or 1.8, Phoenix
LiveView 1.1 or later, and Ecto 3.13 or later. `Narabe.Migration` needs
`ecto_sql`, which a Phoenix app has already.

Add `{:narabe, "~> 0.1"}` to your deps, then:

```sh
mix deps.get
mix narabe.install
```

The installer edits two files and prints what it changed:

* `assets/js/app.js`: it adds `import { Narabe } from "narabe"` and puts
  `Narabe` in the `hooks` of the `LiveSocket`. When it cannot find the
  `new LiveSocket(...)` call, it changes nothing and prints the lines to
  add.
* `assets/css/app.css`: it adds the import of `narabe.css`, and the
  import of the Sumi theme (`narabe-sumi.css`) as a comment.

Then it says whether your esbuild profile resolves `narabe` (see
`NODE_PATH` below). Give `--dry-run` to see the changes as a diff first.
It does not add what a file already has, so you can run it again.

### The manual steps

In `assets/js/app.js`:

```js
import { Narabe } from "narabe"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Narabe},
})
```

In `assets/css/app.css`, below the other `@import` lines:

```css
@import "../../deps/narabe/priv/static/narabe.css";
/* @import "../../deps/narabe/priv/static/narabe-sumi.css"; */
```

`import { Narabe } from "narabe"` resolves through the `NODE_PATH` of
your esbuild profile, which must have `deps/`. The Phoenix generators set
it already. If your profile has none, add it in `config/config.exs`:

```elixir
env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
```

## 2. The table

Each row keeps its place in a position column, a short text that sorts
between its neighbours. `Narabe.Migration.position/2` adds it with the
collation that compares bytes:

```elixir
defmodule MyApp.Repo.Migrations.CreateTodos do
  use Ecto.Migration
  import Narabe.Migration

  def change do
    create table(:todos) do
      add :title, :string
      position()
      timestamps()
    end

    create index(:todos, [:position])
  end
end
```

## 3. The schema

```elixir
defmodule MyApp.Todos.Todo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "todos" do
    field :title, :string
    field :position, :string
    timestamps()
  end

  use Narabe.Ordered

  def changeset(todo, attrs) do
    todo |> cast(attrs, [:title]) |> validate_required([:title])
  end
end
```

`use Narabe.Ordered` declares the order once; here it is one list with
the defaults. A new todo goes last with `Narabe.Ecto.put_position/4`:

```elixir
%Todo{}
|> Todo.changeset(attrs)
|> Narabe.Ecto.put_position(Repo)
|> Repo.insert()
```

## 4. The list

Import the components in the `html_helpers` of your web module:

```elixir
import Narabe.Components
```

Then the LiveView:

```elixir
defmodule MyAppWeb.TodoLive do
  use MyAppWeb, :live_view

  alias MyApp.Repo
  alias MyApp.Todos.Todo

  def mount(_params, _session, socket) do
    todos = Todo |> Narabe.Ecto.ordered() |> Repo.all()
    {:ok, stream(socket, :todos, todos)}
  end

  def render(assigns) do
    ~H"""
    <.sortable_list id="todos" items={@streams.todos} on_move="move" label="To do">
      <:item :let={todo}>{todo.title}</:item>
    </.sortable_list>
    """
  end

  def handle_event("move", params, socket) do
    move = Narabe.Move.parse!(params, Todo)
    result = Narabe.Ecto.move(Repo, Todo, move)
    {:reply, Narabe.Live.reply(result), socket}
  end
end
```

A drop moves the item in the page at once and sends `on_move`. The
LiveView saves the move and replies: `%{ok: true}` keeps the item there,
`%{error: ...}` puts it back and tells the person why. A drop where the
items already were sends nothing.

Try it: drag a todo, or focus one, press Space, the arrows, then Space
again.

## 5. A test

```elixir
import Narabe.Test

test "a todo moves to the top", %{conn: conn} do
  a = Repo.insert!(%Todo{title: "Write the brief", position: "a0"})
  b = Repo.insert!(%Todo{title: "Book the venue", position: "a1"})

  {:ok, view, _html} = live(conn, ~p"/todos")
  move(view, "todos", b.id, before: a.id)
  assert_reply(view, %{ok: true})

  assert Todo |> Narabe.Ecto.ordered() |> Repo.all() |> Enum.map(& &1.id) == [b.id, a.id]
end
```

Next: the [Lists](lists.md) and [Database](database.md) guides.
