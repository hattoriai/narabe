# LazyHTML is a dependency of an app's tests (Phoenix.LiveViewTest needs
# it), not of Narabe: Narabe.Test calls it, and it is not in the PLT.
#
# Ecto.Multi.new/0 builds a MapSet that OTP 29's dialyzer takes as opaque
# through Ecto's own struct type: a warning of Ecto's types, not of the call.
[
  {"lib/narabe/test.ex", :unknown_function},
  {"lib/narabe/ecto.ex", :call_without_opaque},
  {"lib/narabe/ecto/mixed.ex", :call_without_opaque}
]
