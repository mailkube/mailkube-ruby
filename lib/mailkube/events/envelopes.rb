# frozen_string_literal: true

module Mailkube
  module Events
    # The envelope every webhook payload arrives in: a type, a timestamp, and a `data` block.
    #
    # There is deliberately **no `id`** here. The delivery id travels in the `X-Webhook-Id` header,
    # is stable across retries, and is what you deduplicate on — so it belongs to the request, not
    # to the parsed body.
    #
    # `data` is declared on each concrete subclass rather than here, which is what lets
    # {UnknownEvent} hand back a raw Hash without conflicting with a typed sibling.
    class Event < Node
      # @return [String] the event type, e.g. `email.delivered`.
      def type = self["type"]
      # @return [String] when the event occurred.
      def created_at = self["created_at"]
    end

    # A message left the platform for its recipient's server.
    class EmailSentEvent < Event
      # @return [SentData] the event payload.
      def data = block(SentData, "data")
    end

    # A recipient's server accepted the message.
    class EmailDeliveredEvent < Event
      # @return [DeliveredData] the event payload.
      def data = block(DeliveredData, "data")
    end

    # A recipient's server rejected the message permanently.
    class EmailBouncedEvent < Event
      # @return [BouncedData] the event payload.
      def data = block(BouncedData, "data")
    end

    # A recipient's server deferred the message; delivery will be retried.
    class EmailDeliveryDelayedEvent < Event
      # @return [DelayedData] the event payload.
      def data = block(DelayedData, "data")
    end

    # Recipients were suppressed rather than sent to.
    class EmailSuppressedEvent < Event
      # @return [SuppressedData] the event payload.
      def data = block(SuppressedData, "data")
    end

    # A send was accepted for later delivery.
    class EmailScheduledEvent < Event
      # @return [ScheduledData] the event payload.
      def data = block(ScheduledData, "data")
    end

    # A scheduled send never went out.
    class EmailFailedEvent < Event
      # @return [FailedData] the event payload.
      def data = block(FailedData, "data")
    end

    # A recipient opened the message.
    class EmailOpenedEvent < Event
      # @return [OpenedData] the event payload.
      def data = block(OpenedData, "data")
    end

    # A recipient clicked a link in the message.
    class EmailClickedEvent < Event
      # @return [ClickedData] the event payload.
      def data = block(ClickedData, "data")
    end

    # A sending domain's status or onboarding state changed.
    class DomainStatusEvent < Event
      # @return [DomainStatusData] the event payload.
      def data = block(DomainStatusData, "data")
    end

    # A webhook endpoint was enabled, disabled or deleted.
    class WebhookStatusEvent < Event
      # @return [WebhookStatusData] the event payload.
      def data = block(WebhookStatusData, "data")
    end

    # An event type this release has never heard of.
    #
    # Not an error: the contract requires an unknown type to degrade to untyped access so that a
    # receiver keeps working when the platform adds a type, with no SDK upgrade. {#data} is the raw
    # hash, and {Node#[]} reaches anything inside it.
    class UnknownEvent < Event
      # @return [Hash{String => Object}] the payload, undecoded.
      def data = self["data"] || {}
    end
  end
end
