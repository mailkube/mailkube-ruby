# frozen_string_literal: true

# Verify a webhook signature without running a server.
#
#   ruby examples/verify_webhook.rb path/to/fixture.json [more.json...]
#
# The Sinatra and Rails receivers show verification inside a framework. This one strips that away:
# it feeds captured deliveries straight to `verify` so you can see exactly what is accepted and
# what is not. Useful for testing your own handler against saved payloads.
#
# A fixture is JSON: { secret, headers: {...}, body: "<raw body string>", must_verify: bool }.
# The body must be the EXACT bytes the server sent — re-serializing parsed JSON will not reproduce
# the signature, which is the single most common integration bug.

require_relative "../lib/mailkube"
require "json"

abort("usage: ruby examples/verify_webhook.rb <fixture.json> [more.json...]") if ARGV.empty?

failures = 0

ARGV.each do |path|
  fixture = JSON.parse(File.read(path))

  verified = false
  detail = ""
  begin
    event = Mailkube::Webhooks.verify(
      payload: fixture.fetch("body"),
      headers: fixture.fetch("headers"),
      secret: fixture.fetch("secret")
    )
    verified = true
    detail = "event #{event.type}"
  rescue Mailkube::SignatureVerificationError => e
    detail = e.message
  end

  expected = fixture["must_verify"] == true
  ok = verified == expected
  failures += 1 unless ok
  puts format(
    "%<mark>s %<name>s: %<got>s (expected %<want>s) %<detail>s",
    mark: ok ? "ok  " : "BAD ",
    name: fixture.fetch("name", path),
    got: verified ? "verified" : "rejected",
    want: expected ? "verified" : "rejected",
    detail: detail
  )
end

abort("#{failures} fixture(s) did not verify as expected") if failures.positive?
puts "all fixtures behaved as expected"
