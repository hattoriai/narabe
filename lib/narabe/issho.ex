if Code.ensure_loaded?(Issho.Motion) do
  defmodule Narabe.Issho do
    @moduledoc ~S"""
    People and agents seen moving things, with
    [Issho](https://hex.pm/packages/issho): a list, a tree or a board
    shows the item each person is on, the items someone is dragging (in
    their color, with their name) and where they would land, and an agent
    that moves items goes to them and drags them there before the move
    lands, for the people who watch.

    The order is not shared here: it is the order your app keeps (with
    `Narabe.Ecto`, and a broadcast or a stream to the other viewers).
    Narabe carries only who is moving what, and where to.

    ## The list

        <.board
          id="sprint"
          columns={@columns}
          cards={@cards}
          on_move="move"
          issho={[instance: MyApp.Issho, document: "board:7/cards"]}
          user={@current_user}
        />

    `issho` takes the keys of every component of the family
    (`Issho.Join`): the list's document names it in its room (the part
    before the first `"/"`), and the LiveView joins that room for it
    (`on_mount Issho.Live`). The `user` is the person, as `Issho.Actor`
    says them.

    ## Locks

    An item is moved by one at a time: the person who lifts it holds it
    until they drop it or let go, and the others cannot lift it meanwhile
    (they see who holds it). `lock: false` in the list's `issho` turns the
    locks off. A lock is the people's way of not moving over each other,
    not a check: two moves that reach the server both apply, in the order
    they come (`Narabe.Ecto`'s `:serialize`).

    ## An agent

    An agent's tool moves the items as the app does, and lets the people
    see it drag them first:

        def call(%{"card" => card, "column" => column}, ctx) do
          {:ok, participant} = Issho.Tool.Context.join(ctx, "board:7")
          move = %Narabe.Move{ids: [card], parent: column, index: 0}

          Narabe.Issho.move(participant, "board:7/cards", move, fn ->
            Narabe.Ecto.move(Repo, Card, move)
          end)
        end

    `move/5` takes the items' lock, goes to the first item, picks it up,
    goes to the place it lands and waits a moment there (`:pace`), then
    runs the function, then lets go. A person who paused or stopped the
    agent (`Issho.Work`) stops it before the move lands.

    ## Places

    A place in a list is `%{"item" => id}` (the item a person is on), or,
    while they drag, `%{"item" => id, "count" => n, "drag" => gap}` with
    the gap they would drop in: `%{"parent" => id, "after" => id,
    "before" => id, "level" => n}` (the move's own words). Ids are text,
    as the browser has them.
    """

    alias Issho.{Motion, Participant}

    @pace 500

    @doc """
    Moves an agent through a list as it moves items (`Narabe.Move`), runs
    `fun` (the app's move), and lets go; gives what `fun` gives.

    When someone else holds one of the items, the agent does not move it:
    `{:error, {:locked, key}}`, with the holder's key. An agent that a
    person paused or stopped gives Issho's `{:error, {:interrupted, by}}`.

    Options: `:pace`, how long the agent stays at the item and at the
    place it drops it (#{@pace} ms; 0 for none), and `:travel` (`false`:
    the agent is there at once, as `Issho.Motion` says).
    """
    @spec move(GenServer.server(), String.t(), Narabe.Move.t(), (-> result), keyword()) ::
            result | {:error, {:locked, String.t()} | term()}
          when result: term()
    def move(participant, document, %Narabe.Move{} = move, fun, opts \\ [])
        when is_function(fun, 0) do
      travel = Keyword.get(opts, :travel, true)
      pace = Keyword.get(opts, :pace, @pace)
      own = Participant.key(participant)
      ids = Enum.map(move.ids, &to_string/1)

      case Enum.find(
             Enum.map(ids, &holder(lock_states(participant), document, &1)),
             &(&1 not in [nil, own])
           ) do
        nil -> walk(participant, document, move, ids, fun, travel, pace)
        holder -> {:error, {:locked, holder}}
      end
    end

    # The locks of the room, as the states `holder/3` reads.
    defp lock_states(participant) do
      participant
      |> Participant.locks()
      |> Enum.map(fn {place, key} -> %{"key" => key, "state" => %{"locks" => [place]}} end)
    end

    defp walk(participant, document, move, [first | _] = ids, fun, travel, pace) do
      held = place(document, %{"item" => first})

      dragging =
        place(document, %{
          "item" => first,
          "count" => length(ids),
          "drag" => %{
            "parent" => text(move.parent),
            "after" => text(move.after),
            "before" => text(move.before),
            "level" => nil
          }
        })

      with :ok <- Participant.lock(participant, [lock(document, ids, now())]),
           :ok <- Motion.go(participant, held, travel: travel),
           :ok <- Motion.pause(participant, held, pace, travel: travel),
           :ok <- Motion.drag(participant, held, dragging, travel: travel),
           :ok <- Motion.pause(participant, dragging, pace, travel: travel),
           :ok <- present(participant) do
        fun.()
      end
    after
      Participant.aware(participant, %{"place" => nil, "locks" => []})
    end

    defp present(participant) do
      case Participant.interrupted(participant) do
        nil -> :ok
        by -> {:error, {:interrupted, by}}
      end
    end

    defp now, do: System.system_time(:millisecond)
    defp text(nil), do: nil
    defp text(id), do: to_string(id)

    @doc false
    # The lock of items, as a session's awareness holds it: since when.
    @spec lock(String.t(), [String.t()], integer()) :: map()
    def lock(document, ids, since),
      do: %{"doc" => document, "at" => %{"items" => ids, "since" => since}}

    @doc false
    # Who holds an item, of the room's awareness states: the one who took
    # it first (then by key, so every screen agrees), or nil.
    @spec holder([map()], String.t(), String.t()) :: String.t() | nil
    def holder(states, document, id) do
      states
      |> Enum.flat_map(fn %{"key" => key} = state ->
        for %{"doc" => ^document, "at" => %{"items" => items} = at} <-
              get_in(state, ["state", "locks"]) || [],
            id in items,
            do: {at["since"] || 0, key}
      end)
      |> Enum.min(fn -> {nil, nil} end)
      |> elem(1)
    end

    @doc false
    # Every held item of a document, and who holds it.
    @spec holders([map()], String.t()) :: %{String.t() => String.t()}
    def holders(states, document) do
      states
      |> Enum.flat_map(fn %{"key" => key} = state ->
        for %{"doc" => ^document, "at" => %{"items" => items} = at} <-
              get_in(state, ["state", "locks"]) || [],
            id <- items,
            do: {id, {at["since"] || 0, key}}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {id, holders} -> {id, holders |> Enum.min() |> elem(1)} end)
    end

    @doc """
    A place of a list, for `Issho.Motion` or a participant's place:
    `%{"doc" => document, "at" => at}`.

        iex> Narabe.Issho.place("board:7/cards", %{"item" => "42"})
        %{"doc" => "board:7/cards", "at" => %{"item" => "42"}}
    """
    @spec place(String.t(), map()) :: map()
    def place(document, at) when is_binary(document) and is_map(at),
      do: %{"doc" => document, "at" => at}

    @doc """
    Checks a place in a list (its `"at"`): `:ok`, or an error.

        iex> Narabe.Issho.validate(%{"item" => "42", "count" => 2, "drag" => %{"parent" => "7", "after" => nil, "before" => "9", "level" => 2}})
        :ok
        iex> Narabe.Issho.validate(%{"option" => "done"})
        {:error, :invalid_place}
    """
    @spec validate(term()) :: :ok | {:error, :invalid_place}
    def validate(nil), do: :ok

    def validate(%{} = at) do
      if Enum.all?(at, &part?/1), do: :ok, else: {:error, :invalid_place}
    end

    def validate(_other), do: {:error, :invalid_place}

    defp part?({"item", id}), do: id?(id) and id != nil
    defp part?({"count", n}), do: is_integer(n) and n > 0 and n <= 10_000

    defp part?({"drag", %{} = gap}) do
      Enum.all?(gap, fn
        {key, id} when key in ["parent", "after", "before"] -> id?(id)
        {"level", nil} -> true
        {"level", n} -> is_integer(n) and n > 0 and n <= 10_000
        _other -> false
      end)
    end

    defp part?({coordinate, value}) when coordinate in ["x", "y"],
      do: is_number(value) and value >= 0 and value <= 1

    defp part?(_other), do: false

    defp id?(nil), do: true
    defp id?(id), do: is_binary(id) and byte_size(id) <= 200
  end
end
