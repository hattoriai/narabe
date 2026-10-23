defmodule Narabe.IsshoTest do
  # Who is moving what in a list, with Issho: people and agents, seen by
  # the others; the order stays the app's.
  use ExUnit.Case, async: false

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Issho.Tool.Context

  doctest Narabe.Issho

  @endpoint NarabeTest.Endpoint

  setup do
    %{room: "board:#{System.unique_integer([:positive])}"}
  end

  defp open(room, user) do
    {:ok, view, _html} =
      live_isolated(build_conn(), NarabeTest.MovingLive,
        session: %{"room" => room, "user" => user}
      )

    view
  end

  defp settle(view) do
    :sys.get_state(view.pid)
    :sys.get_state(view.pid)
  end

  # The last "narabe:people" that a LiveView pushed to its board.
  defp last_push(view) do
    settle(view)
    Process.sleep(30)
    settle(view)
    collect(view, nil)
  end

  defp collect(%{proxy: {ref, _topic, _pid}} = view, last) do
    receive do
      {^ref, {:push_event, "narabe:people", %{id: "board"} = payload}} -> collect(view, payload)
    after
      50 -> last
    end
  end

  defp place(view, at),
    do: view |> with_target("#board-issho") |> render_hook("narabe:place", %{"at" => at})

  test "the others see who is on which item, and where someone drags", %{room: room} do
    ada = open(room, "ada")
    ken = open(room, "ken")
    _ = last_push(ken)

    place(ada, %{"item" => "1"})
    assert %{people: [%{"name" => "Ada", "at" => %{"item" => "1"}}], held: held} = last_push(ken)
    assert held == %{}

    drag = %{"parent" => "2", "after" => nil, "before" => nil, "level" => nil}
    place(ada, %{"item" => "1", "count" => 1, "items" => ["1"], "drag" => drag})

    assert %{
             people: [%{"at" => %{"item" => "1", "drag" => ^drag}}],
             held: %{"1" => %{"name" => "Ada"}}
           } =
             last_push(ken)

    # Ada's own screen: no one else, and nothing held by another.
    assert %{people: [], held: %{}} = last_push(ada)

    place(ada, nil)
    assert %{people: [], held: %{}} = last_push(ken)
  end

  test "a place that is not a list's is not shared", %{room: room} do
    ada = open(room, "ada")
    ken = open(room, "ken")
    _ = last_push(ken)
    place(ada, %{"open" => true, "option" => "x"})
    assert last_push(ken) in [nil, %{people: [], held: %{}, id: "board"}]
  end

  test "the first to lift an item holds it", %{room: room} do
    ada = open(room, "ada")
    ken = open(room, "ken")
    place(ada, %{"item" => "1", "items" => ["1"]})
    _ = last_push(ken)
    place(ken, %{"item" => "1", "items" => ["1", "2"]})
    assert %{held: %{"1" => %{"name" => "Ada"}} = held} = last_push(ken)
    refute Map.has_key?(held, "2")
    assert %{held: %{"2" => %{"name" => "Ken"}} = held} = last_push(ada)
    refute Map.has_key?(held, "1")
  end

  test "an agent goes to the card, drags it, then the app's move lands", %{room: room} do
    ken = open(room, "ken")
    _ = last_push(ken)

    ctx = Context.new(NarabeTest.Issho, %{id: "agent:claude", name: "Claude", kind: :agent})
    {:ok, participant} = Context.join(ctx, room)
    test = self()
    move = %Narabe.Move{ids: [1], parent: 2, index: 0}

    result =
      Narabe.Issho.move(participant, room <> "/cards", move, fn ->
        send(test, {:during, last_push(ken)})
        :saved
      end)

    assert result == :saved

    assert_received {:during,
                     %{
                       people: [
                         %{
                           "name" => "Claude",
                           "kind" => "agent",
                           "at" => %{"item" => "1", "drag" => %{"parent" => "2"}}
                         }
                       ],
                       held: %{"1" => %{"name" => "Claude"}}
                     }}

    assert_receive {_ref, {:push_event, "narabe:people", %{id: "board", people: [], held: held}}}
                   when held == %{},
                   1000
  end

  test "an agent does not move what someone holds", %{room: room} do
    ada = open(room, "ada")
    place(ada, %{"item" => "1", "items" => ["1"]})
    _ = last_push(ada)

    ctx = Context.new(NarabeTest.Issho, %{id: "agent:claude", name: "Claude", kind: :agent})
    {:ok, participant} = Context.join(ctx, room)

    assert {:error, {:locked, "ada"}} =
             Narabe.Issho.move(
               participant,
               room <> "/cards",
               %Narabe.Move{ids: [1], index: 1},
               fn ->
                 flunk("moved")
               end
             )

    # Another card is free.
    assert :ok =
             Narabe.Issho.move(
               participant,
               room <> "/cards",
               %Narabe.Move{ids: [2], index: 0},
               fn -> :ok end,
               pace: 0
             )
  end

  test "an agent that a person paused does not move, and says why", %{room: room} do
    ctx = Context.new(NarabeTest.Issho, %{id: "agent:claude", name: "Claude", kind: :agent})
    {:ok, participant} = Context.join(ctx, room)

    :ok =
      Issho.Work.interrupt(NarabeTest.Issho, room, Issho.Participant.key(participant), :pause,
        by: %{id: "ada", name: "Ada"}
      )

    assert Enum.any?(1..50, fn _ ->
             Process.sleep(10)
             Issho.Participant.interrupted(participant) != nil
           end)

    assert {:error, {:interrupted, _by}} =
             Narabe.Issho.move(participant, room <> "/cards", %Narabe.Move{ids: [1]}, fn ->
               flunk("moved")
             end)
  end

  test "a list with issho needs its user, said" do
    assigns = %{}

    assert_raise ArgumentError, ~r/needs its `user`/, fn ->
      rendered_to_string(~H"""
      <Narabe.Components.sortable_list id="l" items={[]} issho={[instance: NarabeTest.Issho, document: "x:1/l"]} />
      """)
    end
  end
end
