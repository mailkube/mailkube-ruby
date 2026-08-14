# frozen_string_literal: true

# Steep is the half of the type gate that actually reads `lib/`.
#
# `rbs validate` proves the signatures are internally coherent and nothing more: it never loads
# the implementation, so a `sig/` describing methods that do not exist passes it. Steep compares
# the two. Both run in CI; neither is sufficient alone.
target :lib do
  signature "sig"
  check "lib"

  # The stdlib this gem actually uses. RBS ships signatures for each, but only loads the ones a
  # target names, so an unnamed one shows up as "cannot find the declaration of constant" rather
  # than as a missing dependency. Keep this list in step with the `require`s in `lib/`, and keep
  # it in step with the `-r` flags on the `rbs validate` command in the Rakefile and CI.
  library "uri", "time", "openssl", "json", "net-http", "socket", "erb"

  configure_code_diagnostics do |hash|
    # A method in `lib/` that no signature declares is the drift this gate exists to catch. It is
    # a warning by default, which `steep check` exits 0 on, so it is promoted here.
    hash[Steep::Diagnostic::Ruby::UndeclaredMethodDefinition] = :error

    # `MethodDefinitionMissing` (a signature with no implementation) is deliberately NOT enabled.
    # Every model subclasses `Data.define(...)`, whose readers Steep cannot see, so it reports
    # each one as missing. Turning it on would mean deleting the reader signatures that make the
    # models typed at all. Verified against Steep 2.0.0.
  end
end
