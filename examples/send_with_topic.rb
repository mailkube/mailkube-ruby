# frozen_string_literal: true

# Send against a mailing-list topic.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/send_with_topic.rb you@example.com newsletter
#
# A topic is a subscription group your recipients can opt out of individually, and `topic` is the
# slug you configured for it (16 characters max). Sending under one means the unsubscribe link
# removes the recipient from that topic rather than from everything you send.
#
# The slug must already exist and be enabled on the sending domain's apex. An unknown or disabled
# slug is rejected outright, BEFORE the message is charged or queued — so a typo costs you nothing,
# but it does not silently fall back to sending untopiced either. The second half of this example
# triggers that rejection on purpose.

require_relative "../lib/mailkube"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/send_with_topic.rb <recipient@example.com> [topic-slug]")
end
topic = ARGV.fetch(1, "newsletter")

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new

email = client.emails.send(
  from: sender,
  to: recipient,
  subject: %(Sent under the "#{topic}" topic),
  html: "<p>Unsubscribing from this removes you from this topic only.</p>",
  text: "Unsubscribing from this removes you from this topic only.",
  topic: topic
)
puts "accepted #{email.id} under topic #{topic}"

# The negative case: a slug that was never configured.
begin
  client.emails.send(
    from: sender,
    to: recipient,
    subject: "This one never leaves the building",
    text: "You should not be reading this.",
    topic: "no-such-topic"
  )
  abort("expected an unknown topic to be rejected, but it was accepted")
rescue Mailkube::APIError => e
  raise unless e.error_name == Mailkube::ErrorName::TOPIC_NOT_FOUND

  puts "unknown topic correctly rejected: #{e.error_name}"
end
