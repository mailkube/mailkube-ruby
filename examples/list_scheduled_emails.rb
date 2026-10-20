# frozen_string_literal: true

# List the sends still waiting to go out: one page for the metadata, then the lazy walk for the
# rows. Read-only: nothing is scheduled, moved or canceled.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/list_scheduled_emails.rb
#
# `list` returns one page plus its pagination block. `iter_all` is a lazy enumerator that follows
# the links the server issues and fetches the next page only once the walk asks for it, so
# `first(SHOWN)` below means the remaining pages are never requested at all.

require_relative "../lib/mailkube"

SHOWN = 20

client = Mailkube.new # reads MAILKUBE_API_KEY

begin
  first = client.scheduled_emails.list(status: "scheduled")
  puts "page #{first.pagination.current_page}: #{first.data.size} of #{first.pagination.total_count} " \
       "scheduled, more: #{first.more?}"

  client.scheduled_emails.iter_all(status: "scheduled").first(SHOWN).each do |email|
    puts [email.scheduled_at, email.id, email.batch_id || "-", email.subject].join("  ")
  end
  puts "stopped after at most #{SHOWN}; later pages were never fetched"
rescue Mailkube::Error => e
  warn "#{e.class}: #{e.message}"
  exit 1
end
