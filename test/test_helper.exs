# Tests, die ins Netz gehen, laufen nicht mit: sie wuerden rot, wenn ein
# fremder Shop umbaut, und das sagt nichts ueber diesen Code.
#
#     mix test --include external
ExUnit.configure(exclude: [:external])

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Kitrank.Repo, :manual)
