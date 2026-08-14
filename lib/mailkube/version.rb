# frozen_string_literal: true

module Mailkube
  # The released version of this gem.
  #
  # This constant is the **single source of truth** the contract requires: the gemspec reads it
  # (`spec.version = Mailkube::VERSION`) and the User-Agent reads it, so the version on the wire
  # and the version on rubygems.org cannot disagree.
  #
  # The value committed here is a permanent `0.0.0` placeholder and is never updated. On release,
  # semantic-release rewrites this line **in the release runner** just before the gem is built, and
  # commits nothing back to `main` (see `.rules/RELEASE.md`). So a checkout reports `0.0.0` and an
  # installed gem reports the real version: that is intended, not a bug to fix by hardcoding one.
  VERSION = "0.0.0"
end
