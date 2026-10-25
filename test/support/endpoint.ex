defmodule NarabeTest.ErrorHTML do
  @moduledoc "Error pages for the test endpoint."

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule NarabeTest.Router do
  @moduledoc "The router of the test endpoint."
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)
    live("/board", NarabeTest.BoardLive)
    live("/group", NarabeTest.GroupLive)
  end
end

defmodule NarabeTest.Endpoint do
  @moduledoc "A Phoenix endpoint for the `Narabe.Live` and `Narabe.Test` tests. It runs no server."
  use Phoenix.Endpoint, otp_app: :narabe

  plug(Plug.Session, store: :cookie, key: "_narabe_test", signing_salt: "narabe-test")
  plug(NarabeTest.Router)
end
