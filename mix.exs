defmodule Narabe.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/hattoriai/narabe"

  # NARABE_OLDEST=1 resolves the oldest Phoenix and LiveView that Narabe
  # supports, for the CI job that tests them.
  @oldest System.get_env("NARABE_OLDEST") in ["1", "true"]

  def project do
    [
      app: :narabe,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # For the code reloader of the development server (dev.exs). The
      # listener is Phoenix 1.8's, so the oldest versions go without it.
      listeners: if(@oldest, do: [], else: [Phoenix.CodeReloader]),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :esbuild],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/project.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      package: package(),
      docs: docs(),
      description: description(),
      name: "Narabe",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ecto, "~> 3.13"},
      # Narabe.Migration's helpers, and the tests' Postgres.
      {:ecto_sql, "~> 3.13", optional: true},
      {:esbuild, "~> 0.10", only: :dev, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # People and agents seen moving things, with Issho (Narabe.Issho): optional.
      {:issho, "~> 0.4", optional: true},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix, if(@oldest, do: "~> 1.7.14", else: "~> 1.7.14 or ~> 1.8")},
      {:phoenix_ecto, "~> 4.6", only: [:dev, :test]},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, if(@oldest, do: "~> 1.1.0", else: "~> 1.1")},
      {:postgrex, "~> 0.20", only: [:dev, :test]},
      {:myxql, "~> 0.7", only: [:dev, :test]},
      {:ecto_sqlite3, "~> 0.19", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp description do
    "Lists, trees and boards that people reorder, for Phoenix LiveView: drag, keyboard and phones, with the order kept right in your database."
  end

  defp package do
    [
      name: "narabe",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # The bundle files by name: other build output in priv/static never
      # goes into the package.
      files: ~w(
        lib
        priv/static/narabe.esm.js
        priv/static/narabe.cjs.js
        priv/static/narabe.css
        priv/static/narabe-sumi.css
        package.json
        mix.exs
        .formatter.exs
        guides
        README.md
        CHANGELOG.md
        LICENSE
        NOTICE
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      # The banner of the README, at the same relative path in the docs.
      assets: %{"media" => "media"},
      extras: [
        "README.md",
        "guides/quickstart.md",
        "guides/lists.md",
        "guides/trees.md",
        "guides/boards.md",
        "guides/groups.md",
        "guides/database.md",
        "guides/rules.md",
        "guides/collaboration.md",
        "guides/testing.md",
        "guides/theming.md",
        "guides/accessibility.md",
        "guides/limits.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides:
          ~r{guides/(quickstart|lists|trees|boards|groups|database|rules|collaboration|testing|theming)\.md},
        Reference: ["guides/accessibility.md", "guides/limits.md"]
      ],
      groups_for_modules: [
        Components: [Narabe, Narabe.Components, Narabe.Live, Narabe.Messages, Narabe.Tree],
        "Order and moves": [Narabe.Move, Narabe.Rules, Narabe.Position],
        Database: [Narabe.Ecto, Narabe.Ecto.Mixed, Narabe.Ordered, Narabe.Migration],
        "With Issho": [Narabe.Issho],
        Testing: [Narabe.Test]
      ]
    ]
  end

  # The browser tests need their npm packages; `npm ci` runs once.
  defp e2e_deps(_args) do
    unless File.dir?("e2e/node_modules") do
      Mix.Task.run("cmd", ~w(--cd e2e npm ci))
    end
  end

  defp aliases do
    [
      "assets.build": ["narabe.build"],
      dev: "run --no-halt dev.exs",
      "test.e2e": [&e2e_deps/1, "cmd --cd e2e npm test"],
      "test.js": ["cmd --cd assets npm test"],
      # The compile and the asset build run in a child VM: once anything
      # compiles in this VM, Mix no longer finds the tasks of the Hex
      # archive. The check refuses a priv/static with anything but the
      # bundle files.
      release: [
        "cmd mix narabe.build",
        "cmd mix narabe.release_check",
        "hex.publish --yes",
        "cmd git tag v#{@version} -f",
        "cmd git push",
        "cmd git push --tags"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
