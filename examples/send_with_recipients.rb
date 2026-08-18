# frozen_string_literal: true

# Every recipient field and custom headers on one message.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/send_with_recipients.rb you@example.com
#
# `to`, `cc`, `bcc` and `reply_to` each take a single address or an array. The account limit is 50
# recipients per message, counted across to + cc + bcc.
#
# Custom headers carry your own metadata. The API caps them at 20 per message, header names match
# [A-Za-z0-9-] up to 64 characters, and no value may contain CR or LF.

require_relative "../lib/mailkube"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/send_with_recipients.rb <recipient@example.com>")
end

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new

email = client.emails.send(
  from: sender,
  to: [recipient],
  cc: recipient,
  bcc: [recipient],
  # Replies go somewhere other than the sending address.
  reply_to: "support@yourdomain.com",
  subject: "Every recipient field at once",
  html: "<p>to, cc, bcc and reply-to on a single message.</p>",
  text: "to, cc, bcc and reply-to on a single message.",
  headers: {
    "X-Campaign-Id" => "recipients-demo",
    "X-Customer-Tier" => "gold"
  }
)
puts "accepted #{email.id}"
