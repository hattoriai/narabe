defmodule NarabeTest.GroupLive do
  @moduledoc """
  Two lists of one group, kept in memory: the tasks of a project in the
  LiveView, and another project's in a component (its own `phx-target`),
  for Narabe.Test's tests of moves between lists.
  """
  use Phoenix.LiveView

  import Narabe.Components

  def mount(_params, _session, socket) do
    tasks = [
      %{id: 1, title: "Write", project_id: 1},
      %{id: 2, title: "Ship", project_id: 1},
      %{id: 3, title: "Rest", project_id: 2}
    ]

    {:ok, assign(socket, tasks: tasks, left: nil)}
  end

  def render(assigns) do
    ~H"""
    <.sortable_list
      id="launch"
      items={Enum.filter(@tasks, &(&1.project_id == 1))}
      parent={1}
      group="tasks"
      on_move="move"
      on_leave="left"
      item_label={:title}
    />
    <.live_component module={NarabeTest.GroupLive.Project} id="someday" tasks={Enum.filter(@tasks, &(&1.project_id == 2))} />
    <p id="left">{@left && Enum.join(@left["ids"], ",") <> " to " <> @left["to"]}</p>
    """
  end

  def handle_event("move", params, socket), do: move(socket, params)
  def handle_event("left", params, socket), do: {:noreply, assign(socket, left: params)}

  def handle_info({:move, params}, socket) do
    {:reply, _reply, socket} = move(socket, params)
    {:noreply, socket}
  end

  defp move(socket, params) do
    move = Narabe.Move.parse!(params, :id)

    case Narabe.Move.apply(socket.assigns.tasks, move, group: :project_id) do
      {:ok, tasks} -> {:reply, %{ok: true}, assign(socket, tasks: tasks)}
      error -> {:reply, Narabe.Live.reply(error), socket}
    end
  end

  defmodule Project do
    @moduledoc "A project's list in a component: its moves go to the component."
    use Phoenix.LiveComponent

    import Narabe.Components

    def render(assigns) do
      ~H"""
      <div>
        <.sortable_list
          id="someday-list"
          items={@tasks}
          parent={2}
          group="tasks"
          accept={["launch"]}
          on_move="move"
          item_label={:title}
          phx-target={@myself}
        />
        <p id="someday-params">{@params && JSON.encode!(@params)}</p>
      </div>
      """
    end

    def mount(socket), do: {:ok, assign(socket, params: nil)}

    # The tasks are the LiveView's: it applies the move.
    def handle_event("move", params, socket) do
      send(self(), {:move, params})
      {:reply, %{ok: true}, assign(socket, params: params)}
    end
  end
end
