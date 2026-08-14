# frozen_string_literal: true

# Attach a file from raw bytes.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/send_with_attachments.rb you@example.com
#
# Examples are excluded from lint, coverage and the duplication gate: they exist to be read and
# run, not to be shipped.

require_relative "../lib/mailkube"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/send_with_attachments.rb <recipient@example.com>")
end

client = Mailkube.new

# `content` is the raw bytes. The SDK base64-encodes them for the wire, so do not encode first.
# `content_type` is inferred from the filename when you leave it out.
report = Mailkube::Attachment.new(
  filename: "report.csv",
  content: "date,opens,clicks\n2026-08-01,120,18\n",
  content_type: "text/csv"
)

email = client.emails.send(
  from: "Acme <hello@yourdomain.com>",
  to: recipient,
  subject: "Your weekly report",
  text: "The numbers are attached.",
  attachments: [report]
)

puts "accepted #{email.id} with 1 attachment"
