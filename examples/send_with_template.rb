# frozen_string_literal: true

# Send from a saved template instead of raw content.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/send_with_template.rb you@example.com <template-uuid>
#
# A send carries **either** raw content (`html`/`text`) **or** a template. Mixing them is a
# server-side validation error rather than a silent precedence rule.

require_relative "../lib/mailkube"

recipient = ARGV.fetch(0) { abort("usage: ruby examples/send_with_template.rb <recipient> <template-uuid>") }
template_id = ARGV.fetch(1) { abort("usage: ruby examples/send_with_template.rb <recipient> <template-uuid>") }

# The verified sender this account may send from. Override per environment; the
# fallback is a placeholder and will be rejected until you set your own domain.
sender = ENV.fetch("MAILKUBE_FROM", "Acme <hello@yourdomain.com>")

client = Mailkube.new

begin
  email = client.emails.send(
    from: sender,
    to: recipient,
    subject: "Your order shipped",
    template_id: template_id,
    # Omit `template_version` to render whatever is published; pin a number to freeze it.
    template_version: "latest",
    variables: { "first_name" => "Sam", "tracking_url" => "https://example.com/track/123" }
  )
  puts "accepted #{email.id}"
rescue Mailkube::NotFoundError
  warn "no template #{template_id} on this account"
  exit 1
rescue Mailkube::InvalidRequestError => e
  # `missing_required_variable` and `template_not_published` both land here.
  warn "#{e.error_name}: #{e.message}"
  exit 1
end
