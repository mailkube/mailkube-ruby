# frozen_string_literal: true

require_relative "lib/mailkube/version"

Gem::Specification.new do |spec|
  spec.name = "mailkube"
  # The version has exactly one source of truth and this reads it. Never write a literal here:
  # a second copy is how a gem ends up reporting a version it is not.
  spec.version = Mailkube::VERSION
  spec.authors = ["Mail Tactic Corporation"]
  spec.summary = "The official Ruby SDK for mailkube"
  # Distinct from the summary on purpose: `gem build` warns when the two are identical, and
  # RubyGems renders them in different places.
  spec.description = "The official Ruby SDK for mailkube Zero runtime dependencies, with RBS " \
                     "signatures shipped in the gem."
  spec.homepage = "https://github.com/mailkube/mailkube-ruby"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.4"

  # `homepage_uri` is deliberately absent: `spec.homepage` already supplies it, and repeating the
  # same URL under two metadata keys makes `gem build` warn that only one will be shown.
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    # The GitHub Releases page IS the changelog: releases commit nothing back to `main`, so
    # there is no CHANGELOG.md to link. See .rules/RELEASE.md.
    "changelog_uri" => "#{spec.homepage}/releases",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "documentation_uri" => "https://rubydoc.info/gems/mailkube",
    "rubygems_mfa_required" => "true"
  }

  # Ship the library, its signatures and the licence, and nothing else. `git ls-files` is
  # deliberately not used: it makes the built gem depend on the checkout being a git working
  # tree, which is false in a release runner that downloads a tarball.
  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "LICENSE", "NOTICE", "README.md"]
  spec.require_paths = ["lib"]

  # This gem has **no runtime dependencies**, and that is a feature: it is installed into other
  # people's applications, where every dependency is a version conflict waiting to happen.
  # Everything it needs (net/http, json, openssl, uri, time) is stdlib. Before adding one, check
  # whether stdlib already does the job.
end
