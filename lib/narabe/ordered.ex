defmodule Narabe.Ordered do
  @moduledoc """
  A schema's order, declared once: the options of `Narabe.Ecto` that every
  call on the schema then takes.

      defmodule MyApp.Board.Card do
        use Ecto.Schema

        schema "cards" do
          field :title, :string
          field :position, :string
          belongs_to :column, MyApp.Board.Column
        end

        use Narabe.Ordered, group: :column_id
      end

      defmodule MyApp.Docs.Page do
        use Ecto.Schema

        schema "pages" do
          field :title, :string
          field :kind, :string
          field :position, :string
          belongs_to :parent, __MODULE__
        end

        use Narabe.Ordered,
          group: :parent_id,
          tree: true,
          kind: :kind,
          rules: [nest: true, max_depth: 8, leaves: ["file"]]
      end

  Then `Narabe.Ecto.move(Repo, Page, move)` knows the rest, and an option
  given to a call wins over the schema's.

  Options: those of `Narabe.Ecto` (`:group`, `:tree`, `:position`,
  `:rules`, `:kind`, `:group_kind`, `:lock`, `:rebalance_at`).
  """

  @allowed [:group, :tree, :position, :rules, :kind, :group_kind, :lock, :rebalance_at]

  defmacro __using__(opts) do
    opts = Macro.expand_literals(opts, __CALLER__)

    quote bind_quoted: [opts: opts, allowed: @allowed] do
      for {key, _value} <- opts, key not in allowed do
        raise ArgumentError, "Narabe.Ordered: unknown option #{inspect(key)}"
      end

      @narabe_options opts

      @doc false
      def __narabe__, do: @narabe_options
    end
  end
end
