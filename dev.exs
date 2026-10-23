# The Narabe development server: `mix dev`, then http://localhost:4097.
#
# A list, a tree, a board and a tree picker, kept in SQLite through
# Narabe.Ecto (tmp/dev-PORT.sqlite3, made afresh at each start). Open a page in
# two windows: a move in one shows in the other. The browser tests in e2e/
# run against it.
#
# The bundle rebuilds and the page reloads on a change.
#
# Query params of every page: `locale` (a BCP 47 locale), `theme=sumi`,
# `dark=1`, `refuse=1` (the server refuses every move, and the page puts
# the items back).
#
# Environment:
#
#   * PORT - the HTTP port (4097).
#   * NARABE_DEV_WATCH - "false" starts no esbuild watcher and no live
#     reload, for the browser tests; the bundle must be built first.

port = "PORT" |> System.get_env("4097") |> String.to_integer()
watch? = System.get_env("NARABE_DEV_WATCH") != "false"

Application.put_env(:phoenix, :json_library, JSON)
Logger.configure(level: :info)

File.mkdir_p!("tmp")
database = Path.expand("tmp/dev-#{port}.sqlite3", __DIR__)
for suffix <- ["", "-wal", "-shm"], do: File.rm(database <> suffix)

Application.put_env(:narabe, NarabeDev.Repo, database: database, pool_size: 5, log: false)

Application.put_env(:narabe, NarabeDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  code_reloader: watch?,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: port],
  live_view: [signing_salt: "narabe-dev-live-view-salt"],
  pubsub_server: NarabeDev.PubSub,
  render_errors: [formats: [html: NarabeDev.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("narabe-development-secret-", 3),
  server: true,
  url: [host: "localhost"],
  watchers:
    if(watch?,
      do: [narabe_esm: {Esbuild, :install_and_run, [:narabe_esm, ~w(--watch)]}],
      else: []
    ),
  live_reload: [patterns: [~r"priv/static/.*\.(js|css)$", ~r"lib/narabe/.*\.ex$"]]
)

defmodule NarabeDev.Repo do
  use Ecto.Repo, otp_app: :narabe, adapter: Ecto.Adapters.SQLite3
end

defmodule NarabeDev.Migration do
  use Ecto.Migration
  import Narabe.Migration

  def change do
    create table(:tasks) do
      add(:title, :string)
      position()
    end

    create table(:pages) do
      add(:title, :string)
      add(:kind, :string)
      add(:parent_id, references(:pages))
      position()
    end

    create(index(:pages, [:parent_id, :position]))

    create table(:columns) do
      add(:name, :string)
      position()
    end

    create table(:cards) do
      add(:title, :string)
      add(:label, :string)
      add(:column_id, references(:columns))
      position()
    end

    create(index(:cards, [:column_id, :position]))
  end
end

defmodule NarabeDev.Task do
  use Ecto.Schema

  schema "tasks" do
    field(:title, :string)
    field(:position, :string)
  end

  use Narabe.Ordered
end

defmodule NarabeDev.Page do
  use Ecto.Schema

  schema "pages" do
    field(:title, :string)
    field(:kind, :string)
    field(:position, :string)
    belongs_to(:parent, NarabeDev.Page)
  end

  use Narabe.Ordered,
    group: :parent_id,
    tree: true,
    kind: :kind,
    rules: [nest: true, max_depth: 6, leaves: ["file"]]
end

defmodule NarabeDev.Column do
  use Ecto.Schema

  schema "columns" do
    field(:name, :string)
    field(:position, :string)
  end

  use Narabe.Ordered
end

defmodule NarabeDev.Card do
  use Ecto.Schema

  schema "cards" do
    field(:title, :string)
    field(:label, :string)
    field(:position, :string)
    belongs_to(:column, NarabeDev.Column)
  end

  use Narabe.Ordered, group: :column_id
end

defmodule NarabeDev.Seeds do
  @moduledoc "The made-up rows of the development pages."
  alias NarabeDev.{Card, Column, Page, Repo, Task}

  def run do
    Ecto.Migrator.up(Repo, 1, NarabeDev.Migration, log: false)
    reset()
  end

  # Every row again, as at the start (the browser tests start each test so).
  def reset do
    for table <- ~w(cards columns tasks), do: Repo.query!("DELETE FROM #{table}")
    Repo.query!("UPDATE pages SET parent_id = NULL")
    Repo.query!("DELETE FROM pages")
    # The ids start again at 1.
    Repo.query!("DELETE FROM sqlite_sequence")

    tasks =
      ["Write the brief", "Book the venue", "Order the badges", "Email the speakers"] ++
        ["Print the schedule", "Test the projector", "Buy coffee", "Set up the stream"]

    keys = Narabe.Position.between_many(nil, nil, length(tasks))
    Repo.insert_all(Task, Enum.zip_with(tasks, keys, &%{title: &1, position: &2}))

    tree = [
      {"Handbook", "folder",
       [
         {"Welcome", "page", []},
         {"Engineering", "folder",
          [
            {"Code review", "page", []},
            {"On call", "page", []},
            {"Releases", "page", [{"Checklist", "file", []}]}
          ]},
         {"Design", "folder", [{"Brand", "page", []}, {"Logo.svg", "file", []}]}
       ]},
      {"Projects", "folder",
       [{"Narabe", "page", [{"Roadmap", "page", []}]}, {"Erabi", "page", []}]},
      {"Archive", "folder", for(n <- 1..6, do: {"Old notes #{n}", "page", []})},
      {"Inbox", "page", []}
    ]

    insert_pages(tree, nil)

    columns = ["To do", "Doing", "Review", "Done"]
    column_keys = Narabe.Position.between_many(nil, nil, length(columns))

    for {name, key} <- Enum.zip(columns, column_keys) do
      column = Repo.insert!(%Column{name: name, position: key})
      cards = cards(name)
      keys = Narabe.Position.between_many(nil, nil, max(length(cards), 1))

      for {{title, label}, key} <- Enum.zip(cards, keys),
          do: Repo.insert!(%Card{title: title, label: label, column_id: column.id, position: key})
    end
  end

  defp insert_pages(nodes, parent_id) do
    keys = Narabe.Position.between_many(nil, nil, max(length(nodes), 1))

    for {{title, kind, children}, key} <- Enum.zip(nodes, keys) do
      page = Repo.insert!(%Page{title: title, kind: kind, parent_id: parent_id, position: key})
      insert_pages(children, page.id)
    end
  end

  defp cards("To do"),
    do: [
      {"Search in the docs", "feature"},
      {"Dark mode for charts", "design"},
      {"Flaky upload test", "bug"}
    ]

  defp cards("Doing"), do: [{"Keyboard moves on boards", "feature"}, {"Lazy children", "feature"}]
  defp cards("Review"), do: [{"Rebalance a window", "perf"}]
  defp cards("Done"), do: [{"Position keys", "feature"}, {"MySQL nodelay", "perf"}]
end

defmodule NarabeDev.Layouts do
  @moduledoc """
  The root layout: the style sheets, the import map and the LiveSocket.
  `?theme=sumi` also loads narabe-sumi.css; `?dark=1` is the dark theme.
  """
  use Phoenix.Component

  def root(assigns) do
    assigns = Map.put(assigns, :sumi, assigns.conn.params["theme"] == "sumi")

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={@conn.params["dark"] && "dark"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Narabe development</title>
        <link rel="stylesheet" href="/assets/narabe.css" />
        <link :if={@sumi} rel="stylesheet" href="/assets/narabe-sumi.css" />
        <style>
          body { font-family: system-ui, sans-serif; margin: 0; background: var(--narabe-background); color: var(--narabe-text); }
          main { max-width: 64rem; margin: 0 auto; padding: 1.5rem 1rem 6rem; }
          nav a { margin-right: 1rem; color: inherit; }
          h1 { font-size: 1.5rem; margin: 1.25rem 0 0.25rem; }
          .lede { color: var(--narabe-muted); margin: 0 0 1.25rem; }
          .panel { max-width: 26rem; border: 1px solid var(--narabe-border); border-radius: 10px; padding: 0.5rem; }
          .tag { font-size: 0.75rem; padding: 0.05rem 0.4rem; border-radius: 4px; background: var(--narabe-surface); color: var(--narabe-muted); }
          .kind { width: 1rem; text-align: center; color: var(--narabe-muted); }
          pre { background: var(--narabe-surface); padding: 0.75rem; border-radius: 8px; font-size: 0.8125rem; overflow: auto; }
          .add { width: 100%; padding: 0.375rem; font: inherit; color: var(--narabe-muted); background: none; border: 0; border-radius: 6px; text-align: left; cursor: pointer; }
          .add:hover { background: var(--narabe-hover); }
        </style>
        <script type="importmap">
          {
            "imports": {
              "phoenix": "/vendor/phoenix/phoenix.mjs",
              "phoenix_live_view": "/vendor/phoenix_live_view/phoenix_live_view.esm.js",
              "narabe": "/assets/narabe.esm.js"
            }
          }
        </script>
        <script type="module">
          import { Socket } from "phoenix";
          import { LiveSocket } from "phoenix_live_view";
          import { Narabe, mountNarabe } from "narabe";

          const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content");
          if (document.querySelector("[data-phx-main]")) {
            const liveSocket = new LiveSocket("/live", Socket, { hooks: { Narabe }, params: { _csrf_token: csrf } });
            liveSocket.connect();
            window.liveSocket = liveSocket;
          } else {
            mountNarabe();
          }
        </script>
      </head>
      <body>
        <main>
          <nav>
            <a href="/">List</a>
            <a href="/tree">Tree</a>
            <a href="/board">Board</a>
            <a href="/picker">Picker</a>
          </nav>
          {@inner_content}
        </main>
      </body>
    </html>
    """
  end
end

defmodule NarabeDev.Live do
  @moduledoc "What the development pages share: the locale, `refuse`, and the last move."
  import Phoenix.Component

  def on_mount(:default, params, _session, socket) do
    {:cont,
     assign(socket,
       locale: params["locale"] || "en",
       refuse: params["refuse"] == "1",
       last_move: nil
     )}
  end

  @doc "Applies a move unless the page refuses them: what `Narabe.Ecto.move/4` returns."
  def move(socket, queryable, schema, params, opts \\ []) do
    if socket.assigns.refuse do
      {:error, "This page refuses every move (refuse=1)"}
    else
      Narabe.Ecto.move(NarabeDev.Repo, queryable, Narabe.Move.parse!(params, schema), opts)
    end
  end
end

defmodule NarabeDev.ListLive do
  @moduledoc "A list in a stream: moves are saved and shown to the other viewers."
  use Phoenix.LiveView
  import Narabe.Components
  alias NarabeDev.{Repo, Task}

  on_mount(NarabeDev.Live)

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NarabeDev.PubSub, "tasks")
    {:ok, socket |> stream(:tasks, tasks()) |> assign(order: order())}
  end

  defp tasks, do: Task |> Narabe.Ecto.ordered() |> Repo.all()
  defp order, do: Enum.map_join(tasks(), ",", & &1.id)

  def render(assigns) do
    ~H"""
    <h1>A list</h1>
    <p class="lede">Drag a task, or focus one and press Space, the arrows, then Space. Shift or Ctrl selects several.</p>
    <div class="panel">
      <.sortable_list id="tasks" items={@streams.tasks} on_move="move" multiple label="Tasks" locale={@locale}>
        <:item :let={task}>{task.title}</:item>
        <:actions :let={task}><button type="button" phx-click="done" phx-value-id={task.id}>Done</button></:actions>
      </.sortable_list>
    </div>
    <p>Order: <span id="order">{@order}</span></p>
    <pre id="last-move">{@last_move && JSON.encode!(@last_move)}</pre>
    """
  end

  def handle_event("move", params, socket) do
    result = NarabeDev.Live.move(socket, Task, Task, params)

    if match?({:ok, _}, result) do
      Phoenix.PubSub.broadcast_from(
        NarabeDev.PubSub,
        self(),
        "tasks",
        {:moved, elem(result, 1), Narabe.Move.parse!(params, Task)}
      )
    end

    {:reply, Narabe.Live.reply(result), assign(socket, last_move: params, order: order())}
  end

  def handle_event("done", _params, socket), do: {:noreply, socket}

  def handle_info(:changed, socket),
    do: {:noreply, socket |> stream(:tasks, tasks(), reset: true) |> assign(order: order())}

  def handle_info({:moved, tasks, move}, socket) do
    {:noreply, socket |> Narabe.Live.stream_move(:tasks, tasks, move) |> assign(order: order())}
  end
end

defmodule NarabeDev.TreeLive do
  @moduledoc """
  A tree of pages: folders hold pages and files, files hold nothing, six
  levels at most; rename with F2; the Archive's children load as it opens.
  """
  use Phoenix.LiveView
  import Narabe.Components
  alias NarabeDev.{Page, Repo}

  on_mount(NarabeDev.Live)

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NarabeDev.PubSub, "pages")
    archive = Repo.get_by!(Page, title: "Archive")
    {:ok, socket |> assign(archive: archive.id, loaded: MapSet.new()) |> load()}
  end

  # The Archive's children stay in the database until it opens.
  defp load(socket) do
    pages = Page |> Narabe.Ecto.ordered() |> Repo.all()
    %{archive: archive, loaded: loaded} = socket.assigns
    under = MapSet.new(Narabe.Ecto.descendants(Repo, Page, archive))

    shown =
      if MapSet.member?(loaded, archive),
        do: pages,
        else: Enum.reject(pages, &MapSet.member?(under, &1.id))

    assign(socket, pages: shown, order: outline(pages))
  end

  defp outline(pages) do
    pages
    |> Narabe.Tree.rows()
    |> Enum.map_join(" ", &"#{String.duplicate(">", &1.level - 1)}#{&1.item.title}")
  end

  def render(assigns) do
    ~H"""
    <h1>A tree</h1>
    <p class="lede">Drag a page into a folder, or press Space and the arrows (Left and Right change the level). F2 renames.</p>
    <div class="panel">
      <.tree
        id="pages"
        items={@pages}
        item_label={:title}
        item_kind={:kind}
        rules={Page}
        item_children={&(&1.id == @archive and not MapSet.member?(@loaded, @archive))}
        on_move="move"
        on_rename="rename"
        on_expand="expand"
        expanded={[]}
        filter
        multiple
        phone={:drill}
        label="Pages"
        locale={@locale}
      >
        <:item :let={page}>
          <span class="kind" aria-hidden="true">{%{"folder" => "📁", "file" => "📎"}[page.kind] || "📄"}</span>
          <span data-narabe-label>{page.title}</span>
        </:item>
      </.tree>
    </div>
    <p>Outline: <span id="order">{@order}</span></p>
    <pre id="last-move">{@last_move && JSON.encode!(@last_move)}</pre>
    """
  end

  def handle_event("move", params, socket) do
    result = NarabeDev.Live.move(socket, Page, Page, params)

    if match?({:ok, _}, result),
      do: Phoenix.PubSub.broadcast_from(NarabeDev.PubSub, self(), "pages", :changed)

    {:reply, Narabe.Live.reply(result), socket |> assign(last_move: params) |> load()}
  end

  def handle_event("rename", %{"id" => id, "name" => name}, socket) do
    page = Repo.get!(Page, id)
    page |> Ecto.Changeset.change(title: String.slice(name, 0, 80)) |> Repo.update!()
    Phoenix.PubSub.broadcast_from(NarabeDev.PubSub, self(), "pages", :changed)
    {:noreply, load(socket)}
  end

  def handle_event("expand", %{"id" => id}, socket) do
    Process.sleep(300)
    {:noreply, socket |> update(:loaded, &MapSet.put(&1, String.to_integer(id))) |> load()}
  end

  def handle_info(:changed, socket), do: {:noreply, load(socket)}
end

defmodule NarabeDev.BoardLive do
  @moduledoc "A kanban board: cards move within and across columns, and the columns move too."
  use Phoenix.LiveView
  import Narabe.Components
  alias NarabeDev.{Card, Column, Repo}

  on_mount(NarabeDev.Live)

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NarabeDev.PubSub, "board")
    {:ok, load(socket)}
  end

  defp load(socket) do
    columns = Column |> Narabe.Ecto.ordered() |> Repo.all()
    cards = Card |> Narabe.Ecto.ordered() |> Repo.all()

    order =
      Enum.map_join(columns, " | ", fn c ->
        c.name <>
          ": " <>
          (cards |> Enum.filter(&(&1.column_id == c.id)) |> Enum.map_join(",", & &1.title))
      end)

    assign(socket, columns: columns, cards: cards, order: order)
  end

  def render(assigns) do
    ~H"""
    <h1>A board</h1>
    <p class="lede">Drag cards within and across columns, and columns by their handle. On a phone, hold a card, then drag.</p>
    <.board id="board" columns={@columns} cards={@cards} on_move="move" move_columns multiple label="Sprint" locale={@locale} item_label={:title}>
      <:column :let={column}>{column.name}</:column>
      <:card :let={card}>
        <div>{card.title}</div>
        <span class="tag">{card.label}</span>
      </:card>
      <:footer :let={column}><button type="button" class="add" phx-click="add" phx-value-column={column.id}>+ Add a card</button></:footer>
    </.board>
    <p>Board: <span id="order">{@order}</span></p>
    <pre id="last-move">{@last_move && JSON.encode!(@last_move)}</pre>
    """
  end

  def handle_event("move", %{"columns" => true} = params, socket) do
    result = NarabeDev.Live.move(socket, Column, Column, params)
    changed(result)
    {:reply, Narabe.Live.reply(result), socket |> assign(last_move: params) |> load()}
  end

  def handle_event("move", params, socket) do
    result = NarabeDev.Live.move(socket, Card, Card, params)
    changed(result)
    {:reply, Narabe.Live.reply(result), socket |> assign(last_move: params) |> load()}
  end

  def handle_event("add", %{"column" => column}, socket) do
    column = String.to_integer(column)
    position = Narabe.Ecto.insert_position(Repo, Card, :last, in: column)
    Repo.insert!(%Card{title: "New card", label: "new", column_id: column, position: position})
    changed({:ok, nil})
    {:noreply, load(socket)}
  end

  defp changed({:ok, _}),
    do: Phoenix.PubSub.broadcast_from(NarabeDev.PubSub, self(), "board", :changed)

  defp changed(_), do: :ok

  def handle_info(:changed, socket), do: {:noreply, load(socket)}
end

defmodule NarabeDev.PickerLive do
  @moduledoc "A tree picker in a form: where to move a page."
  use Phoenix.LiveView
  import Narabe.Components
  alias NarabeDev.{Page, Repo}

  on_mount(NarabeDev.Live)

  def mount(_params, _session, socket) do
    page = Repo.get_by!(Page, title: "Code review")
    folders = Page |> Narabe.Ecto.ordered() |> Repo.all() |> Enum.filter(&(&1.kind == "folder"))

    {:ok,
     assign(socket,
       page: page,
       folders: folders,
       form: to_form(%{"parent_id" => page.parent_id}, as: :move),
       posted: %{}
     )}
  end

  def render(assigns) do
    ~H"""
    <h1>A tree picker</h1>
    <p class="lede">Move “{@page.title}” to a folder.</p>
    <.form for={@form} id="move-form" phx-change="validate" phx-submit="save">
      <div class="panel">
        <.tree_picker field={@form[:parent_id]} items={@folders} item_label={:title} label="Folder" locale={@locale} />
      </div>
      <p><button type="submit">Move</button></p>
    </.form>
    <pre id="posted" data-json={JSON.encode!(@posted)}>{JSON.encode!(@posted)}</pre>
    """
  end

  def handle_event("validate", params, socket),
    do: {:noreply, assign(socket, posted: Map.drop(params, ["_target"]))}

  def handle_event("save", params, socket), do: {:noreply, assign(socket, posted: params)}
end

defmodule NarabeDev.ResetController do
  use Phoenix.Controller, formats: [:html]

  def reset(conn, _params) do
    NarabeDev.Seeds.reset()

    for topic <- ~w(tasks pages board),
        do: Phoenix.PubSub.broadcast(NarabeDev.PubSub, topic, :changed)

    text(conn, "ok")
  end
end

defmodule NarabeDev.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {NarabeDev.Layouts, :root})
  end

  scope "/" do
    pipe_through(:browser)
    live("/", NarabeDev.ListLive)
    live("/tree", NarabeDev.TreeLive)
    live("/board", NarabeDev.BoardLive)
    live("/picker", NarabeDev.PickerLive)
  end

  scope "/" do
    get("/reset", NarabeDev.ResetController, :reset)
  end
end

defmodule NarabeDev.ErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule NarabeDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :narabe

  @session [store: :cookie, key: "_narabe_dev", signing_salt: "narabe-dev"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])

  if System.get_env("NARABE_DEV_WATCH") != "false" do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.Static, at: "/assets", from: Path.expand("priv/static", __DIR__))
  plug(Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"})
  plug(Plug.Static, at: "/vendor/phoenix_live_view", from: {:phoenix_live_view, "priv/static"})

  plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: JSON)
  plug(Plug.Session, @session)
  plug(NarabeDev.Router)
end

# The script's process ends after this file, so the server runs in a task
# that stays alive; `mix run --no-halt` keeps the VM up.
Task.async(fn ->
  if watch?, do: {:ok, _apps} = Application.ensure_all_started(:esbuild)
  {:ok, _apps} = Application.ensure_all_started(:ecto_sqlite3)

  {:ok, _pid} =
    Supervisor.start_link(
      [{Phoenix.PubSub, name: NarabeDev.PubSub}, NarabeDev.Repo, NarabeDev.Endpoint],
      strategy: :one_for_one
    )

  NarabeDev.Seeds.run()
  IO.puts("Narabe development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
