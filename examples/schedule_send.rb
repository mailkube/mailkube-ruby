# frozen_string_literal: true

# Schedule a send for later, then inspect the acknowledgement.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/schedule_send.rb you@example.com
#
# A scheduled send is acknowledged 202 with a richer body than an immediate one. The same `Email`
# model carries both — the contract's "widen, never union" rule — and `#scheduled?` tells them
# apart.

require_relative "../lib/mailkube"
require "time"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/schedule_send.rb <recipient@example.com>")
end

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new

# Must be in the future and within your plan's scheduling horizon. A `Time` is rendered to
# ISO-8601 for you; a string is passed through untouched, so it must already carry an offset.
due = Time.now.utc + (60 * 60)

email = client.emails.send(
  from: sender,
  to: recipient,
  subject: "Your reminder",
  text: "This was scheduled an hour ago.",
  scheduled_at: due
)

puts "scheduled? #{email.scheduled?}"
puts "id         #{email.id}"
puts "status     #{email.status}"
puts "due        #{email.scheduled_at}"

# The ack is lean by design. Ask the collection for the rest.
full = client.scheduled_emails.get(email.id)
puts "subject    #{full.subject}"
puts "recipients #{full.recipients}"
