# frozen_string_literal: true

# List, paginate, retrieve, reschedule and cancel scheduled emails.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/manage_scheduled_emails.rb you@example.com
#
# The example schedules its own email under a unique batch id and then works only inside that
# batch. That is deliberate: an unfiltered `list`/`iter_all` walks every pending send on the
# account, and taking `page.data.first` from it means rescheduling and cancelling whichever
# message happened to come back first — someone else's. Scoping to a batch you just created keeps
# the example bounded, repeatable, and safe to run against a live key.
#
# Only `scheduled`, `canceled` and `failed` can be listed. A sent email has left the collection,
# so `status: "sent"` is a validation error rather than an empty result.

require_relative "../lib/mailkube"
require "time"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/manage_scheduled_emails.rb <recipient@example.com>")
end

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new
batch_id = "example-manage-#{Time.now.to_i}"

created = client.emails.send(
  from: sender,
  to: recipient,
  subject: "Scheduled for management",
  html: "<p>This one exists to be listed, moved and cancelled.</p>",
  scheduled_at: Time.now.utc + (60 * 60),
  batch_id: batch_id
)
puts "scheduled #{created.id} in batch #{batch_id}"

# Reads are rate-limited (60/minute by default), so pace a script that walks pages rather than
# relying on catching the 429.
sleep 0.6

# One page, with the pagination block.
page = client.scheduled_emails.list(status: "scheduled", batch_id: batch_id)
puts "#{page.pagination.total_count} scheduled, page #{page.pagination.current_page}, more? #{page.more?}"
page.data.each { |email| puts "  #{email.id}  #{email.scheduled_at}  #{email.recipients}" }
sleep 0.6

# Every page, lazily. `iter_all` follows the server's `next` link rather than counting pages, and
# makes no request until you iterate it — so `.first(5)` fetches exactly the pages it needs.
due_soon = client.scheduled_emails.iter_all(
  status: "scheduled",
  batch_id: batch_id,
  scheduled_at_lte: Time.now.utc + (24 * 60 * 60)
)
puts "next 5 due within a day:"
due_soon.first(5).each { |email| puts "  #{email.id}  #{email.scheduled_at}" }

target = page.data.first
abort("nothing scheduled in this batch") if target.nil?

sleep 0.6
puts "fetched #{client.scheduled_emails.get(target.id).subject}"
sleep 0.6

# Push it back an hour. The content is immutable; only the due time and batch can change.
moved = client.scheduled_emails.update(target.id, scheduled_at: Time.now.utc + (2 * 60 * 60))
puts "moved #{moved.id} to #{moved.scheduled_at}"
sleep 0.6

begin
  canceled = client.scheduled_emails.cancel(target.id)
  puts "cancelled #{canceled.id} -> #{canceled.status}"
rescue Mailkube::InvalidRequestError => e
  # `scheduled_email_not_pending`: it went out between the list and the cancel.
  warn "#{e.error_name}: #{e.message}"
end
