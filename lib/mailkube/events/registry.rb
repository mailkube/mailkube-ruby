# frozen_string_literal: true

module Mailkube
  module Events
    # Every event type this release knows, mapped to the envelope that models it.
    #
    # **This constant is the catalogue.** The known-type set is derived from it (`REGISTRY.keys`)
    # and never written out beside it: a hand-maintained parallel list that missed an entry would
    # route a wired-up event to {UnknownEvent} at runtime, silently, with no test failing.
    #
    # Registering an event is adding one row here. There is no second place to update.
    REGISTRY = {
      "email.sent" => EmailSentEvent,
      "email.delivered" => EmailDeliveredEvent,
      "email.bounced" => EmailBouncedEvent,
      "email.delivery_delayed" => EmailDeliveryDelayedEvent,
      "email.suppressed" => EmailSuppressedEvent,
      "email.scheduled" => EmailScheduledEvent,
      "email.failed" => EmailFailedEvent,
      "email.opened" => EmailOpenedEvent,
      "email.clicked" => EmailClickedEvent,
      "domain.status" => DomainStatusEvent,
      "webhook.status" => WebhookStatusEvent
    }.freeze
  end
end
