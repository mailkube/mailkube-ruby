# frozen_string_literal: true

# Retry a send safely with an idempotency key.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/send_with_idempotency.rb you@example.com
#
# There are no built-in retries in this SDK, so retrying is your call — and a naive retry after a
# timeout can send the same message twice, because a request that never returned may still have
# succeeded. An idempotency key makes the retry safe: the server remembers the first response for
# that key (24 hours by default) and replays it byte for byte instead of sending again.
#
# The key is fingerprinted against the request body. Reusing a key with a DIFFERENT body is an
# error rather than a silent replay, which is what stops a recycled key from swallowing a real
# second message.

require_relative "../lib/mailkube"

recipient = ARGV.fetch(0) do
  abort("usage: ruby examples/send_with_idempotency.rb <recipient@example.com>")
end

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new

# In real code this is a stable id for the thing you are sending about — an order id, a job id —
# not a random value, otherwise a retry generates a new key and sends twice.
idempotency_key = "order-#{Time.now.to_i}"

params = {
  from: sender,
  to: recipient,
  subject: "Sent at most once",
  html: "<p>Retrying this send cannot duplicate it.</p>",
  text: "Retrying this send cannot duplicate it.",
  idempotency_key: idempotency_key
}

first = client.emails.send(**params)
puts "first  call: #{first.id}"

# Pretend the first response never reached us and we retried.
replay = client.emails.send(**params)
puts "replayed   : #{replay.id}"

if first.id != replay.id
  abort("expected the same id back, got #{first.id} then #{replay.id} — that is a second send")
end
puts "same id returned: the retry was replayed, not resent"

# Same key, different body: refused rather than replayed.
begin
  client.emails.send(**params.merge(subject: "A different message entirely"))
  abort("expected a reused key with a changed body to be rejected")
rescue Mailkube::Error => e
  puts "key reuse with a changed body correctly rejected: #{e.error_name}"
end
