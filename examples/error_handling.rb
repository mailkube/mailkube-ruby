# frozen_string_literal: true

# The errors you will actually hit, and how to tell them apart.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/error_handling.rb you@example.com
#
# Every failure arrives as a `Mailkube::Error` subclass carrying `error_name` — the server's stable
# machine-readable name — alongside `status_code`. Branch on `error_name`, never on the
# human-readable message, which is free to change.
#
# Nothing here sends a message: each call is designed to be refused.

require_relative "../lib/mailkube"
require "time"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/error_handling.rb <recipient@example.com>")
end

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new
failures = 0

expect = lambda do |label, expected, &check|
  check.call
  warn "BAD  #{label}: expected #{expected}, but the call succeeded"
  failures += 1
rescue Mailkube::Error => e
  ok = e.error_name == expected
  failures += 1 unless ok
  puts "#{ok ? 'ok  ' : 'BAD '} #{label}: #{e.error_name} (#{e.status_code})"
end

# A message with no body at all: html, text and template_id are mutually required-one-of.
expect.call("missing body", Mailkube::ErrorName::VALIDATION_ERROR) do
  client.emails.send(from: sender, to: recipient, subject: "No body")
end

# scheduled_at must carry an offset and be strictly in the future.
expect.call("past scheduled_at", Mailkube::ErrorName::VALIDATION_ERROR) do
  client.emails.send(
    from: sender, to: recipient, subject: "Yesterday", text: "...",
    scheduled_at: Time.now.utc - 60
  )
end

# batch_id is a grouping label for scheduled sends and means nothing without scheduled_at.
expect.call("batch_id without scheduled_at", Mailkube::ErrorName::VALIDATION_ERROR) do
  client.emails.send(from: sender, to: recipient, subject: "Ungrouped", text: "...", batch_id: "b1")
end

# A sent email has left the scheduled collection, so filtering for it is a contract error rather
# than an empty page — the distinction tells you your assumption was wrong.
expect.call('list status "sent"', Mailkube::ErrorName::VALIDATION_ERROR) do
  client.scheduled_emails.list(status: "sent")
end

# A bad key is refused identically whether it is malformed, unknown or absent, so nothing about
# the key space leaks.
expect.call("bad api key", Mailkube::ErrorName::INVALID_API_KEY) do
  anonymous = Mailkube.new(api_key: "mk_notarealkey_#{'0' * 64}")
  anonymous.emails.send(from: sender, to: recipient, subject: "Nope", text: "...")
end

abort("#{failures} case(s) did not behave as documented") if failures.positive?
puts "all error cases behaved as documented"
