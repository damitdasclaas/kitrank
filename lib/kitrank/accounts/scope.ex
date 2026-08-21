defmodule Kitrank.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Kitrank.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Kitrank.Accounts.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Darf dieser Scope den Admin-Bereich sehen?

  Bewusst hier und nicht im Template: die Frage "wer darf was" soll an genau
  einer Stelle beantwortet werden.
  """
  def admin?(%__MODULE__{user: %User{is_admin: true}}), do: true
  def admin?(_scope), do: false
end
