if Code.ensure_loaded?(Issho.Live) do
  defmodule Narabe.Issho.Presence do
    @moduledoc false
    # The room of a list with `issho`: the LiveView joins it (Issho.Live),
    # puts where its person is in the list (the browser says it, as
    # "narabe:place"), and tells the list who else is in it, agents too,
    # and who holds which items ("narabe:people"). The order stays the
    # app's: this carries only who is moving what, and where to.
    #
    # In the session's awareness state, which the components of a LiveView
    # share in a room: "place", `%{"doc" => list's document, "at" => at}`
    # (Narabe.Issho's places), and "locks", the items a person holds.

    use Phoenix.LiveComponent

    @impl true
    def render(assigns) do
      ~H"""
      <div id={@id} hidden data-narabe-issho={@list}></div>
      """
    end

    @impl true
    def update(%{issho: {event, _key, _payload}}, socket)
        when event in ["aware", "presence_diff"],
        do: {:ok, push_people(socket)}

    def update(%{issho: _other}, socket), do: {:ok, socket}

    def update(assigns, socket) do
      socket = assign(socket, Map.take(assigns, [:id, :list, :join, :user]))
      {:ok, if(connected?(socket), do: join(socket), else: socket)}
    end

    # Joins the room once, and asks for its events.
    defp join(%{assigns: %{joined: true}} = socket), do: socket

    defp join(socket) do
      %{join: join, user: user, id: id} = socket.assigns

      case Issho.Live.join(join.instance, user, join.room, Issho.Join.grant_opts(join)) do
        {:ok, _session} ->
          Issho.Live.subscribe(join.room, {__MODULE__, id}, on_release: fn -> leave(join) end)

          socket
          |> assign(joined: true, own: Issho.Identity.new(user).key)
          |> push_people()

        {:error, _reason} ->
          assign(socket, joined: false)
      end
    end

    @impl true
    def handle_event("narabe:place", %{"at" => at}, %{assigns: %{joined: true}} = socket) do
      if valid?(at) and socket.assigns.join.can == :write do
        put_place(socket.assigns.join, at)
      end

      # Its own change is no event of the room's here: who holds the lock
      # may have changed.
      {:noreply, push_people(socket)}
    end

    def handle_event("narabe:place", _params, socket), do: {:noreply, socket}

    # The person's place in the list, or none; a place elsewhere stays.
    # While they drag, the person holds the dragged items (unless the
    # list's `issho` says `lock: false`), from when they first took them.
    defp put_place(join, at) do
      doc = join.document
      state = Issho.Live.awareness(join.room)

      place =
        cond do
          at != nil -> Narabe.Issho.place(doc, Map.delete(at, "items"))
          match?(%{"doc" => ^doc}, state["place"]) -> nil
          true -> state["place"]
        end

      {mine, others} = Enum.split_with(state["locks"] || [], &match?(%{"doc" => ^doc}, &1))

      locks =
        case at do
          %{"items" => [_ | _] = items} ->
            if Map.get(join.extra, :lock, true),
              do: [Narabe.Issho.lock(doc, items, since(mine)) | others],
              else: others

          _other ->
            others
        end

      Issho.Live.aware(join.room, state |> Map.put("place", place) |> Map.put("locks", locks))
    end

    # A place, and the ids of the items dragged (for the lock).
    defp valid?(nil), do: true

    defp valid?(%{} = at) do
      {items, place} = Map.pop(at, "items", [])

      is_list(items) and length(items) <= 10_000 and
        Enum.all?(items, &(is_binary(&1) and byte_size(&1) <= 200)) and
        Narabe.Issho.validate(place) == :ok
    end

    defp valid?(_other), do: false

    defp since([%{"at" => %{"since" => since}} | _]), do: since
    defp since(_none), do: System.system_time(:millisecond)

    defp leave(join), do: put_place(join, nil)

    # The others in the list, as it draws them: each person once, with
    # the place of the session that is in the list; and who holds what.
    defp push_people(%{assigns: %{joined: true}} = socket) do
      %{join: join, own: own, list: list} = socket.assigns
      doc = join.document
      metas = Issho.Live.people(join.room)
      # The room's states, and this session's own, which may be newer.
      states =
        Map.values(Issho.Live.states(join.room)) ++
          [%{"key" => own, "state" => Issho.Live.awareness(join.room)}]

      people =
        states
        |> Enum.flat_map(fn
          %{"key" => key, "state" => %{"place" => %{"doc" => ^doc, "at" => at}}}
          when key != own ->
            [{key, at}]

          _other ->
            []
        end)
        |> Enum.uniq_by(&elem(&1, 0))
        |> Enum.map(fn {key, at} -> person(key, at, metas) end)
        |> Enum.sort_by(&{&1["name"] || "", &1["key"]})

      held =
        for {id, key} <- Narabe.Issho.holders(states, doc), key != own, into: %{} do
          {id, key |> person(%{}, metas) |> Map.take(["key", "name", "color", "kind"])}
        end

      push_event(socket, "narabe:people", %{id: list, people: people, held: held})
    end

    defp push_people(socket), do: socket

    # Issho's color of a person, with Issho's own default when its style
    # sheet is not on the page.
    @palette ~w(#2563eb #db2777 #059669 #d97706 #7c3aed #dc2626 #0891b2 #65a30d)

    defp person_color(key) do
      index = Issho.Color.index(key)
      "var(--issho-person-#{index}, #{Enum.at(@palette, index - 1)})"
    end

    defp person(key, at, metas) do
      meta =
        case Map.get(metas, key) do
          %{metas: [meta | _]} -> meta
          %{"metas" => [meta | _]} -> meta
          _none -> %{}
        end

      %{
        "key" => key,
        "name" => meta["name"] || key,
        "avatar" => meta["avatar"],
        "color" => Issho.Color.sanitize(meta["color"]) || person_color(key),
        "kind" => if(meta["kind"] in ["agent", "service"], do: "agent", else: "human"),
        "at" => if(Narabe.Issho.validate(at) == :ok, do: at || %{}, else: %{})
      }
    end
  end
end
