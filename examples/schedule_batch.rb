# frozen_string_literal: true

# Schedule several sends under one batch label, then move or cancel them as a unit.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/schedule_batch.rb you@example.com
#
# `batch_id` is only valid alongside `scheduled_at`; sending it on an immediate send is a
# validation error.

require_relative "../lib/mailkube"
require "time"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/schedule_batch.rb <recipient@example.com>")
end

client = Mailkube.new
batch_id = "welcome-#{Time.now.to_i}"
due = Time.now.utc + (60 * 60)

3.times do |index|
  client.emails.send(
    from: "Acme <hello@yourdomain.com>",
    to: recipient,
    subject: "Onboarding step #{index + 1}",
    text: "Step #{index + 1} of 3.",
    scheduled_at: due + (index * 60),
    batch_id: batch_id
  )
end
puts "scheduled 3 emails under #{batch_id}"

# Move the whole batch. There is deliberately no `batch_id:` in the body — the path names the
# batch, and the server rejects a second one rather than guess which batch actually moves.
moved = client.scheduled_emails.batches.update(batch_id, scheduled_at: due + (24 * 60 * 60))
puts "rescheduled #{moved.rescheduled_count} to #{moved.scheduled_at}"

# Cancel it. An unknown batch is a no-op reporting 0 rather than a 404, so a count of 0 is not
# a failure — it means nothing was pending.
canceled = client.scheduled_emails.batches.cancel(batch_id)
puts "cancelled #{canceled.canceled_count}"
