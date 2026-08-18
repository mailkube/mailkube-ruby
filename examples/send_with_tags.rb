# frozen_string_literal: true

# Tag a send so you can filter, export and dashboard by it later.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/send_with_tags.rb you@example.com
#
# Tags ride along on delivery webhooks too, so the same labels show up on `email.delivered`.
# They are **not encrypted**: never put personal data in a tag value.

require_relative "../lib/mailkube"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/send_with_tags.rb <recipient@example.com>")
end

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new

# The server validates these: names and values are limited to [A-Za-z0-9_-], a name to 16
# characters and a value to 32, at most 20 tags per send, and names must be unique. A value may
# be blank.
email = client.emails.send(
  from: sender,
  to: recipient,
  subject: "Welcome aboard",
  html: "<p>Glad you are here.</p>",
  tags: [
    Mailkube::Tag.new(name: "campaign", value: "welcome"),
    Mailkube::Tag.new(name: "cohort", value: "2026-08"),
    Mailkube::Tag.new(name: "transactional")
  ]
)

puts "accepted #{email.id}, tagged campaign=welcome"
