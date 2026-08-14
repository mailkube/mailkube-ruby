# frozen_string_literal: true

# List, paginate, retrieve, reschedule and cancel scheduled emails.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/manage_scheduled_emails.rb
#
# Only `scheduled`, `canceled` and `failed` can be listed. A sent email has left the collection,
# so `status: "sent"` is a validation error rather than an empty result.

require_relative "../lib/mailkube"
require "time"

client = Mailkube.new

# One page, with the pagination block.
page = client.scheduled_emails.list(status: "scheduled")
puts "#{page.pagination.total_count} scheduled, page #{page.pagination.current_page}, more? #{page.more?}"
page.data.each { |email| puts "  #{email.id}  #{email.scheduled_at}  #{email.recipients}" }

# Every page, lazily. `iter_all` follows the server's `next` link rather than counting pages, and
# makes no request until you iterate it — so `.first(5)` fetches exactly the pages it needs.
due_soon = client.scheduled_emails.iter_all(
  status: "scheduled",
  scheduled_at_lte: Time.now.utc + (24 * 60 * 60)
)
puts "next 5 due within a day:"
due_soon.first(5).each { |email| puts "  #{email.id}  #{email.scheduled_at}" }

target = page.data.first
abort("nothing scheduled to demonstrate with") if target.nil?

# Push it back an hour. The content is immutable; only the due time and batch can change.
moved = client.scheduled_emails.update(target.id, scheduled_at: Time.now.utc + (2 * 60 * 60))
puts "moved #{moved.id} to #{moved.scheduled_at}"

begin
  canceled = client.scheduled_emails.cancel(target.id)
  puts "cancelled #{canceled.id} -> #{canceled.status}"
rescue Mailkube::InvalidRequestError => e
  # `scheduled_email_not_pending`: it went out between the list and the cancel.
  warn "#{e.error_name}: #{e.message}"
end
