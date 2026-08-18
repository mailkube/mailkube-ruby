# frozen_string_literal: true

# Runnable documentation: the smallest useful program this gem supports.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/simple_send.rb you@example.com
#
# Examples are linted and parsed in CI like the rest of the gem (they are copied by customers),
# but nothing executes them, so they stay out of coverage.

require_relative "../lib/mailkube"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/simple_send.rb <recipient@example.com>")
end

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new # reads MAILKUBE_API_KEY

begin
  email = client.emails.send(
    from: sender,
    to: recipient,
    subject: "Hello from mailkube-ruby",
    html: "<p>It works!</p>",
    text: "It works!",
    # Set an idempotency key on anything you might retry: the API replays the original response
    # instead of sending twice.
    idempotency_key: "example-#{Time.now.to_i}"
  )
  puts "accepted #{email.id} (message-id #{email.message_id || "none"})"
rescue Mailkube::RateLimitError => e
  warn "rate limited; retry after #{e.retry_after}s"
rescue Mailkube::Error => e
  warn "#{e.class}: #{e.message}"
  exit 1
end
