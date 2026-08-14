# frozen_string_literal: true

# Receive and verify mailkube webhooks in a Rails app.
#
# This file is a controller, not a runnable script: drop it in as
# `app/controllers/mailkube_webhooks_controller.rb` and route it with
#
#   get  "/webhooks/mailkube" => "mailkube_webhooks#register"
#   post "/webhooks/mailkube" => "mailkube_webhooks#receive"
#
# Two Rails-specific things matter here, and both are easy to get wrong.
#
# 1. **`request.raw_post`, never `params`.** The signature is computed over the exact bytes that
#    arrived. `params` has been parsed, and re-encoding it reorders keys and normalizes
#    whitespace, so the digest will not match.
#
# 2. **`request.headers` works.** It is `ActionDispatch::Http::Headers`, which is Enumerable but
#    not a Hash, and whose `#each` yields CGI env names like `HTTP_X_WEBHOOK_SIG`. This SDK
#    normalizes both spellings, so you can pass it straight through.
class MailkubeWebhooksController < ActionController::Base
  # Mailkube signs the request; Rails' CSRF token has nothing to do with it.
  skip_forgery_protection

  # Answer the one-time endpoint-registration challenge.
  #
  # Mailkube probes a new or re-pointed endpoint with
  # `GET ...?hub.mode=subscribe&hub.challenge=<token>` and persists it **only** if the body echoes
  # that token verbatim with a 200. Without this, registration is rejected and no event is ever
  # delivered.
  def register
    return head :bad_request unless params["hub.mode"] == "subscribe"

    render plain: params.fetch("hub.challenge", "")
  end

  def receive
    event = Mailkube::Webhooks.verify(
      payload: request.raw_post,
      headers: request.headers,
      secret: Rails.application.credentials.mailkube_webhook_secret
    )

    # `X-Webhook-Id` is stable across retries: deduplicate on it before doing any real work.
    ProcessMailkubeEvent.perform_later(request.headers["X-Webhook-Id"], event.to_h)

    head :ok
  rescue Mailkube::SignatureVerificationError
    head :bad_request
  end
end

# A sketch of the job the controller hands off to. Verify fast, acknowledge fast, work later:
# mailkube retries on a non-2xx, so slow work inside the request is how you get duplicates.
class ProcessMailkubeEvent < ApplicationJob
  def perform(delivery_id, payload)
    return if AlreadyProcessed.exists?(delivery_id: delivery_id)

    # `event.to_h` round-trips to exactly what the server sent, unknown fields included, so
    # re-parsing here loses nothing.
    event = Mailkube::Webhooks.parse_event(JSON.generate(payload))

    case event
    when Mailkube::Events::EmailBouncedEvent
      Contact.find_by(email: event.data.bounce.recipient)&.mark_bounced!(event.data.bounce.reason)
    when Mailkube::Events::EmailClickedEvent
      Click.create!(email_id: event.data.email_id, url: event.data.click.link)
    when Mailkube::Events::UnknownEvent
      # A type newer than this gem. Log it rather than dropping it: `event.data` is the raw hash.
      Rails.logger.info("unhandled mailkube event #{event.type}: #{event.data.inspect}")
    end

    AlreadyProcessed.create!(delivery_id: delivery_id)
  end
end
