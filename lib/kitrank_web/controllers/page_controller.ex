defmodule KitrankWeb.PageController do
  use KitrankWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
