# frozen_string_literal: true

# Receive and verify mailkube webhooks in a Sinatra app.
#
#   gem install sinatra
#   MAILKUBE_WEBHOOK_SECRET=... ruby examples/webhook_receiver_sinatra.rb
#
# Sinatra is deliberately not a dependency of this gem — it has none — so install it yourself to
# run this file.

require "sinatra"
require_relative "../lib/mailkube"

SECRET = ENV.fetch("MAILKUBE_WEBHOOK_SECRET")

# Answer mailkube's one-time endpoint-registration challenge.
#
# When you create an endpoint, or re-point an existing one, mailkube probes it with
# `GET ...?hub.mode=subscribe&hub.challenge=<token>` and persists it **only** if the body echoes
# that token verbatim with a 200. Skip this and registration is rejected, so no event is ever
# delivered — verifying signatures below is necessary but not sufficient on its own.
get "/webhooks/mailkube" do
  halt 400, "unexpected GET" unless params["hub.mode"] == "subscribe"

  content_type "text/plain"
  params.fetch("hub.challenge", "")
end

post "/webhooks/mailkube" do
  # Verify against the bytes you received. Never parse the body and re-encode it first: JSON
  # round-tripping reorders keys and normalizes whitespace, and the signature will not match.
  event = begin
    Mailkube::Webhooks.verify(payload: request.body.read, headers: request.env, secret: SECRET)
  rescue Mailkube::SignatureVerificationError
    halt 400, "invalid signature"
  end

  # `X-Webhook-Id` is stable across retries. Deduplicate on it before doing any real work.
  delivery_id = request.env["HTTP_X_WEBHOOK_ID"]

  case event
  when Mailkube::Events::EmailBouncedEvent
    puts "[#{delivery_id}] bounce #{event.data.bounce.recipient}: " \
         "#{event.data.bounce.code} #{event.data.bounce.reason}"
  when Mailkube::Events::EmailClickedEvent
    puts "[#{delivery_id}] click #{event.data.email_id} -> #{event.data.click.link}"
  when Mailkube::Events::UnknownEvent
    # A type newer than this gem knows about. Still readable, still forwardable.
    puts "[#{delivery_id}] unknown event #{event.type}: #{event.data.inspect}"
  else
    puts "[#{delivery_id}] #{event.type} for #{event.data.email_id}"
  end

  status 200
  "ok"
end
