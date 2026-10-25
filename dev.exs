# The Narabe development server: `mix dev`, then http://localhost:4097.
#
# A list, a tree, a board, a tree picker, and lists whose items move
# between them (a group), kept in SQLite through
# Narabe.Ecto (tmp/dev-PORT.sqlite3, made afresh at each start). Open a page in
# two windows: a move in one shows in the other. The browser tests in e2e/
# run against it.
#
# The bundle rebuilds and the page reloads on a change.
#
# Query params of every page: `locale` (a BCP 47 locale), `theme=sumi`,
# `dark=1`, `sumi=smoke` (the Sumi theme on one of Sumi's seven themes),
# `refuse=1` (the server refuses every move, and the page puts the items
# back).
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

    create table(:projects) do
      add(:name, :string)
      position()
    end

    create table(:todos) do
      add(:title, :string)
      add(:kind, :string)
      add(:project_id, references(:projects))
      position()
    end

    create(index(:todos, [:project_id, :position]))
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

defmodule NarabeDev.Project do
  use Ecto.Schema

  schema "projects" do
    field(:name, :string)
    field(:position, :string)
  end

  use Narabe.Ordered
end

defmodule NarabeDev.Todo do
  use Ecto.Schema

  schema "todos" do
    field(:title, :string)
    field(:kind, :string)
    field(:position, :string)
    belongs_to(:project, NarabeDev.Project)
  end

  use Narabe.Ordered, group: :project_id, kind: :kind
end

defmodule NarabeDev.Seeds do
  @moduledoc "The made-up rows of the development pages."
  alias NarabeDev.{Card, Column, Page, Project, Repo, Task, Todo}

  def run do
    Ecto.Migrator.up(Repo, 1, NarabeDev.Migration, log: false)
    reset()
  end

  # Every row again, as at the start (the browser tests start each test so).
  def reset do
    for table <- ~w(cards columns tasks todos projects),
        do: Repo.query!("DELETE FROM #{table}")

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

    projects = ["Launch", "Website", "Someday", "Errands"]
    project_keys = Narabe.Position.between_many(nil, nil, length(projects))

    for {name, key} <- Enum.zip(projects, project_keys) do
      project = Repo.insert!(%Project{name: name, position: key})
      todos = todos(name)
      keys = Narabe.Position.between_many(nil, nil, length(todos))

      for {{title, kind}, key} <- Enum.zip(todos, keys),
          do: Repo.insert!(%Todo{title: title, kind: kind, project_id: project.id, position: key})
    end
  end

  defp todos("Launch"), do: [{"Write the launch post", "task"}, {"Record the demo", "task"}]
  defp todos("Website"), do: [{"New pricing page", "task"}, {"Fix the footer", "task"}]
  defp todos("Someday"), do: [{"Learn the cello", "task"}, {"Pick up the dry cleaning", "errand"}]
  defp todos("Errands"), do: [{"Buy stamps", "errand"}, {"Return the library books", "errand"}]

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
  `?theme=sumi` also loads narabe-sumi.css; `?dark=1` is the dark theme;
  `?sumi=smoke` (any of Sumi's seven themes) loads narabe-sumi.css on that
  theme of Sumi, to see every list in each.
  """
  use Phoenix.Component

  # Sumi's themes, as the lists read them: the page, the surface, the line,
  # the text, the muted text's alpha, the accent (blade), the text on it and
  # the error (Sumi's own CSS needs Tailwind, which this app has not; these
  # are its values).
  @sumi_themes [
    {"dark", "Ink", "oklch(12% 0.003 270)", "oklch(16% 0.004 270)", "oklch(20% 0.005 270)",
     "oklch(95% 0.012 85)", 0.5, "#e84a1c", "oklch(12% 0.003 270)", "oklch(58% 0.22 25)"},
    {"smoke", "Smoke", "oklch(27% 0.005 270)", "oklch(30.5% 0.006 270)", "oklch(34% 0.007 270)",
     "oklch(92% 0.01 85)", 0.62, "oklch(72% 0.13 168)", "oklch(27% 0.005 270)",
     "oklch(58% 0.22 25)"},
    {"stone", "Stone", "oklch(20% 0.006 70)", "oklch(23.5% 0.007 70)", "oklch(27% 0.008 70)",
     "oklch(95% 0.01 85)", 0.52, "oklch(78% 0.13 82)", "oklch(20% 0.006 70)",
     "oklch(58% 0.22 25)"},
    {"lacquer", "Lacquer", "oklch(14% 0.022 25)", "oklch(18% 0.026 25)", "oklch(22% 0.03 25)",
     "oklch(93% 0.016 75)", 0.53, "oklch(63% 0.21 24)", "oklch(14% 0.022 25)",
     "oklch(58% 0.22 25)"},
    {"light", "Paper", "oklch(96% 0.01 85)", "oklch(93% 0.012 85)", "oklch(89% 0.014 80)",
     "oklch(15% 0.003 270)", 0.65, "#e84a1c", "oklch(12% 0.003 270)", "oklch(55% 0.22 25)"},
    {"snow", "Snow", "oklch(99.5% 0.001 270)", "oklch(97% 0.003 270)", "oklch(92.5% 0.005 270)",
     "oklch(20% 0.006 270)", 0.65, "oklch(50% 0.17 262)", "oklch(100% 0 0)",
     "oklch(55% 0.22 25)"},
    {"silk", "Silk", "oklch(97.5% 0.012 350)", "oklch(95% 0.016 350)", "oklch(91.5% 0.02 350)",
     "oklch(22% 0.012 350)", 0.65, "oklch(56% 0.21 358)", "oklch(100% 0 0)", "oklch(55% 0.22 25)"}
  ]

  defp sumi_style(id) do
    case List.keyfind(@sumi_themes, id, 0) do
      {_, _, page, surface, line, text, muted, accent, on_accent, error} ->
        """
        :root {
          --color-base-100: #{page}; --color-base-200: #{surface}; --color-base-300: #{line};
          --color-base-content: #{text}; --sumi-text-muted: oklch(from #{text} l c h / #{muted});
          --color-sumi-blade: #{accent}; --color-primary-content: #{on_accent}; --color-error: #{error};
        }
        """

      nil ->
        ""
    end
  end

  def root(assigns) do
    look = assigns.conn.params["sumi"]
    look = if List.keymember?(@sumi_themes, look, 0), do: look

    assigns =
      assign(assigns,
        sumi: assigns.conn.params["theme"] == "sumi" or look != nil,
        look: look,
        themes: @sumi_themes
      )

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={@look || (@conn.params["dark"] && "dark")}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Narabe development</title>
        <link rel="stylesheet" href="/assets/narabe.css" />
        <link :if={@sumi} rel="stylesheet" href="/assets/narabe-sumi.css" />
        {@look && Phoenix.HTML.raw("<style>" <> sumi_style(@look) <> "</style>")}
        <style>
          body { font-family: system-ui, sans-serif; margin: 0; background: var(--narabe-background); color: var(--narabe-text); }
          main { max-width: 64rem; margin: 0 auto; padding: 1.5rem 1rem 6rem; }
          nav a { margin-right: 1rem; color: inherit; }
          nav + nav { margin-top: 0.5rem; color: var(--narabe-muted); }
          nav a[aria-current="page"] { color: var(--narabe-text); font-weight: 600; }
          h1 { font-size: 1.5rem; margin: 1.25rem 0 0.25rem; }
          .lede { color: var(--narabe-muted); margin: 0 0 1.25rem; }
          .panel { max-width: 26rem; border: 1px solid var(--narabe-border); border-radius: 10px; padding: 0.5rem; }
          .tag { font-size: 0.75rem; padding: 0.05rem 0.4rem; border-radius: 4px; background: var(--narabe-surface); color: var(--narabe-muted); }
          .kind { width: 1rem; text-align: center; color: var(--narabe-muted); }
          pre { background: var(--narabe-surface); padding: 0.75rem; border-radius: 8px; font-size: 0.8125rem; overflow: auto; }
          .add { width: 100%; padding: 0.375rem; font: inherit; color: var(--narabe-muted); background: none; border: 0; border-radius: 6px; text-align: left; cursor: pointer; }
          .add:hover { background: var(--narabe-hover); }
          .side { display: grid; grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr)); gap: 1rem; margin-top: 1rem; align-items: start; }
          .side .panel { max-width: none; }
          h2 { font-size: 1rem; margin: 0.25rem 0.5rem 0.5rem; }
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
            <a href="/group">Group</a>
            <a href="/folders">Folders</a>
          </nav>
          <nav aria-label="Sumi's themes">
            Sumi: <a
              :for={{id, name, _, _, _, _, _, _, _, _} <- @themes}
              href={"?sumi=#{id}"}
              aria-current={@look == id && "page"}
            >{name}</a>
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

  @doc "A tree's pages as one line: `>` for each level under the top."
  def outline(pages) do
    pages
    |> Narabe.Tree.rows()
    |> Enum.map_join(" ", &"#{String.duplicate(">", &1.level - 1)}#{&1.item.title}")
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

    assign(socket, pages: shown, order: NarabeDev.Live.outline(pages))
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

defmodule NarabeDev.Policy do
  @moduledoc "The Issho policy of the development pages: everyone may do everything."
  @behaviour Issho.Policy
  @impl true
  def authorize(_identity, _room, _action), do: :ok
end

defmodule NarabeDev.BoardLive do
  @moduledoc """
  A kanban board: cards move within and across columns, and the columns
  move too. In an Issho room (Narabe.Issho): open it as two people
  (`?user=ada`, `?user=ken`) to see each other drag, or let an agent move
  a card.
  """
  use Phoenix.LiveView
  import Narabe.Components
  alias Issho.Tool.Context
  alias NarabeDev.{Card, Column, Repo}

  on_mount(NarabeDev.Live)
  on_mount(Issho.Live)

  @room "board:demo"

  def mount(params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NarabeDev.PubSub, "board")
    name = params["user"] || "ada"
    {:ok, socket |> assign(user: %{id: name, name: String.capitalize(name)}) |> load()}
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
    <p>
      As <a href={"?user=#{if @user.id == "ken", do: "ada", else: "ken"}"}>{if @user.id == "ken", do: "Ada", else: "Ken"}</a> in another window,
      or <button type="button" id="agent" phx-click="agent">let Claude move a card</button>
    </p>
    <.board
      id="board"
      columns={@columns}
      cards={@cards}
      on_move="move"
      move_columns
      multiple
      label="Sprint"
      locale={@locale}
      item_label={:title}
      issho={[instance: NarabeDev.Issho, document: "board:demo/cards"]}
      user={@user}
    >
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

  # The agent: it joins the room, picks up the first card of To do, and
  # drags it to the top of Done, as people watch; the move lands as the
  # app saves it.
  def handle_event("agent", _params, socket) do
    [todo | _] = socket.assigns.columns
    done = List.last(socket.assigns.columns)
    card = Enum.find(socket.assigns.cards, &(&1.column_id == todo.id))
    first = Enum.find(socket.assigns.cards, &(&1.column_id == done.id))

    if card do
      move = %Narabe.Move{ids: [card.id], parent: done.id, before: first && first.id, index: 0}

      Task.start(fn -> agent_move(move) end)
    end

    {:noreply, socket}
  end

  defp agent_move(move) do
    ctx = Context.new(NarabeDev.Issho, %{id: "agent:claude", name: "Claude", kind: :agent})
    {:ok, participant} = Context.join(ctx, @room)
    Narabe.Issho.move(participant, "board:demo/cards", move, fn -> save(move) end, pace: 700)
  end

  defp save(move) do
    with {:ok, _} = ok <- Narabe.Ecto.move(Repo, Card, move) do
      Phoenix.PubSub.broadcast(NarabeDev.PubSub, "board", :changed)
      ok
    end
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

defmodule NarabeDev.GroupLive do
  @moduledoc """
  Lists of one group (`group="todos"`): a board of two projects, a
  project's list in a component, and the errands in a LiveView of their
  own, inside this one. Tasks move between them, by pointer, finger and
  keyboard (Tab); the errands take errands only.
  """
  use Phoenix.LiveView
  import Narabe.Components
  alias NarabeDev.{Project, Repo, Todo}

  on_mount(NarabeDev.Live)

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NarabeDev.PubSub, "todos")
    {:ok, socket |> assign(left: nil) |> load()}
  end

  defp load(socket) do
    projects = Project |> Narabe.Ecto.ordered() |> Repo.all()
    todos = Todo |> Narabe.Ecto.ordered() |> Repo.all()
    by_name = Map.new(projects, &{&1.name, &1})

    order =
      Enum.map_join(projects, " | ", fn p ->
        p.name <>
          ": " <>
          (todos |> Enum.filter(&(&1.project_id == p.id)) |> Enum.map_join(",", & &1.title))
      end)

    assign(socket,
      columns: [by_name["Launch"], by_name["Website"]],
      someday: by_name["Someday"],
      todos: todos,
      order: order
    )
  end

  def render(assigns) do
    ~H"""
    <h1>Lists of a group</h1>
    <p class="lede">Drag a task between the board and the lists, or lift it with Space and press Tab for the next list. The errands take errands only.</p>
    <.board
      id="week"
      columns={@columns}
      cards={@todos}
      card_column={:project_id}
      group="todos"
      on_move="move"
      item_label={:title}
      item_kind={:kind}
      label="Week"
      locale={@locale}
    >
      <:column :let={project}>{project.name}</:column>
      <:card :let={todo}>
        <div>{todo.title}</div>
        <span class="tag">{todo.kind}</span>
      </:card>
    </.board>
    <div class="side">
      <.live_component
        module={NarabeDev.ProjectList}
        id="someday-project"
        project={@someday}
        todos={Enum.filter(@todos, &(&1.project_id == @someday.id))}
        refuse={@refuse}
        locale={@locale}
      />
      {live_render(@socket, NarabeDev.ErrandsLive,
        id: "errands-live",
        session: %{"refuse" => @refuse, "locale" => @locale}
      )}
    </div>
    <p>Projects: <span id="order">{@order}</span></p>
    <pre id="last-move">{@last_move && JSON.encode!(@last_move)}</pre>
    <pre id="last-leave">{@left && JSON.encode!(@left)}</pre>
    """
  end

  def handle_event("move", params, socket) do
    result = NarabeDev.Live.move(socket, Todo, Todo, params)
    Phoenix.PubSub.broadcast(NarabeDev.PubSub, "todos", {:moved, params})
    {:reply, Narabe.Live.reply(result), socket}
  end

  # A move of any list of the page (the errands' LiveView says it too).
  def handle_info({:moved, params}, socket),
    do: {:noreply, socket |> assign(last_move: params) |> load()}

  def handle_info({:left, params}, socket), do: {:noreply, assign(socket, left: params)}
  def handle_info(:changed, socket), do: {:noreply, load(socket)}
end

defmodule NarabeDev.ProjectList do
  @moduledoc "A project's list in a component: its moves go to the component (`phx-target`)."
  use Phoenix.LiveComponent
  import Narabe.Components
  alias NarabeDev.Todo

  def render(assigns) do
    ~H"""
    <section class="panel">
      <h2>{@project.name}</h2>
      <.sortable_list
        id="someday"
        items={@todos}
        parent={@project.id}
        group="todos"
        on_move="move"
        on_leave="left"
        item_label={:title}
        item_kind={:kind}
        label={@project.name}
        locale={@locale}
        phx-target={@myself}
      >
        <:item :let={todo}>{todo.title} <span class="tag">{todo.kind}</span></:item>
      </.sortable_list>
    </section>
    """
  end

  def handle_event("move", params, socket) do
    result = NarabeDev.Live.move(socket, Todo, Todo, params)
    Phoenix.PubSub.broadcast(NarabeDev.PubSub, "todos", {:moved, params})
    {:reply, Narabe.Live.reply(result), socket}
  end

  # Its tasks landed in another list, and stayed there.
  def handle_event("left", params, socket) do
    send(self(), {:left, params})
    {:noreply, socket}
  end
end

defmodule NarabeDev.ErrandsLive do
  @moduledoc """
  The errands, in a LiveView of their own inside the group's page
  (`live_render`): its list takes errands only, in the browser (its
  rules) and on the server.
  """
  use Phoenix.LiveView
  import Ecto.Query
  import Narabe.Components
  alias NarabeDev.{Project, Repo, Todo}

  def mount(_params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NarabeDev.PubSub, "todos")
    project = Repo.get_by!(Project, name: "Errands")

    {:ok,
     socket
     |> assign(project: project, refuse: session["refuse"], locale: session["locale"] || "en")
     |> load()}
  end

  defp load(socket) do
    project = socket.assigns.project

    assign(socket,
      todos: Todo |> where(project_id: ^project.id) |> Narabe.Ecto.ordered() |> Repo.all()
    )
  end

  def render(assigns) do
    ~H"""
    <section class="panel">
      <h2>{@project.name}</h2>
      <.sortable_list
        id="errands"
        items={@todos}
        parent={@project.id}
        group="todos"
        rules={[accepts: %{"root" => ["errand"]}]}
        on_move="move"
        item_label={:title}
        item_kind={:kind}
        label={@project.name}
        locale={@locale}
      >
        <:item :let={todo}>{todo.title} <span class="tag">{todo.kind}</span></:item>
      </.sortable_list>
    </section>
    """
  end

  def handle_event("move", params, socket) do
    move = Narabe.Move.parse!(params, Todo)
    kinds = Todo |> where([t], t.id in ^move.ids) |> select([t], t.kind) |> Repo.all()

    result =
      if Enum.all?(kinds, &(&1 == "errand")),
        do: NarabeDev.Live.move(socket, Todo, Todo, params),
        else: {:error, :not_accepted}

    Phoenix.PubSub.broadcast(NarabeDev.PubSub, "todos", {:moved, params})
    {:reply, Narabe.Live.reply(result), socket}
  end

  def handle_info({:moved, _params}, socket), do: {:noreply, load(socket)}
  def handle_info(:changed, socket), do: {:noreply, load(socket)}
end

defmodule NarabeDev.FoldersLive do
  @moduledoc """
  A tree of folders beside the main view of one folder, a list, in one
  group (`group="pages"`): a page of the list goes into a folder of the
  tree, and a folder of the tree into the list.
  """
  use Phoenix.LiveView
  import Narabe.Components
  alias NarabeDev.{Page, Repo}

  on_mount(NarabeDev.Live)

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NarabeDev.PubSub, "pages")
    handbook = Repo.get_by!(Page, title: "Handbook")
    {:ok, socket |> assign(handbook: handbook) |> load()}
  end

  defp load(socket) do
    pages = Page |> Narabe.Ecto.ordered() |> Repo.all()
    handbook = socket.assigns.handbook

    assign(socket,
      folders: Enum.filter(pages, &(&1.kind == "folder")),
      children: Enum.filter(pages, &(&1.parent_id == handbook.id)),
      order: NarabeDev.Live.outline(pages)
    )
  end

  def render(assigns) do
    ~H"""
    <h1>A tree and a list</h1>
    <p class="lede">Drag a page of the Handbook into a folder of the tree, or a folder into the Handbook. Space lifts, Tab goes to the other one.</p>
    <div class="side">
      <div class="panel">
        <.tree
          id="folders"
          items={@folders}
          item_label={:title}
          item_kind={:kind}
          rules={Page}
          expanded={Enum.map(@folders, & &1.id)}
          group="pages"
          on_move="move"
          label="Folders"
          locale={@locale}
        />
      </div>
      <section class="panel">
        <h2>{@handbook.title}</h2>
        <.sortable_list
          id="handbook"
          items={@children}
          parent={@handbook.id}
          group="pages"
          on_move="move"
          item_label={:title}
          item_kind={:kind}
          label={@handbook.title}
          locale={@locale}
        >
          <:item :let={page}>
            <span class="kind" aria-hidden="true">{%{"folder" => "📁", "file" => "📎"}[page.kind] || "📄"}</span>
            <span data-narabe-label>{page.title}</span>
          </:item>
        </.sortable_list>
      </section>
    </div>
    <p>Outline: <span id="order">{@order}</span></p>
    <pre id="last-move">{@last_move && JSON.encode!(@last_move)}</pre>
    """
  end

  # Both lists send their moves here: a page's parent, in the tree or the list.
  def handle_event("move", params, socket) do
    result = NarabeDev.Live.move(socket, Page, Page, params)

    if match?({:ok, _}, result),
      do: Phoenix.PubSub.broadcast_from(NarabeDev.PubSub, self(), "pages", :changed)

    {:reply, Narabe.Live.reply(result), socket |> assign(last_move: params) |> load()}
  end

  def handle_info(:changed, socket), do: {:noreply, load(socket)}
end

defmodule NarabeDev.ResetController do
  use Phoenix.Controller, formats: [:html]

  def reset(conn, _params) do
    NarabeDev.Seeds.reset()

    for topic <- ~w(tasks pages board todos),
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
    live("/group", NarabeDev.GroupLive)
    live("/folders", NarabeDev.FoldersLive)
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
      [
        {Phoenix.PubSub, name: NarabeDev.PubSub},
        NarabeDev.Repo,
        {Issho,
         name: NarabeDev.Issho,
         pubsub: NarabeDev.PubSub,
         policy: NarabeDev.Policy,
         secret_key_base: String.duplicate("narabe-development-secret-", 3)},
        NarabeDev.Endpoint
      ],
      strategy: :one_for_one
    )

  NarabeDev.Seeds.run()
  IO.puts("Narabe development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
