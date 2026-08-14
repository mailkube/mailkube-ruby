# frozen_string_literal: true

module Mailkube
  module Events
    # The `data` of `email.sent`: the message, plus the delivery attempt that left the platform.
    class SentData < MessageContext
      # @return [DeliveryContext] the send outcome.
      def sent = block(DeliveryContext, "sent")
    end

    # The `data` of `email.delivered`: the message, plus the accepted delivery.
    class DeliveredData < MessageContext
      # @return [DeliveryContext] the delivery outcome.
      def delivery = block(DeliveryContext, "delivery")
    end

    # The `data` of `email.bounced`: the message, plus the receiving server's rejection.
    class BouncedData < MessageContext
      # @return [FailureContext] the bounce, with its SMTP code and reason.
      def bounce = block(FailureContext, "bounce")
    end

    # The `data` of `email.delivery_delayed`: the message, plus the deferral.
    class DelayedData < MessageContext
      # @return [FailureContext] the deferral, with its SMTP code and reason.
      def delay = block(FailureContext, "delay")
    end

    # The `data` of `email.suppressed`: the message, plus who was suppressed.
    class SuppressedData < MessageContext
      # @return [SuppressionContext] the suppressed recipients.
      def suppression = block(SuppressionContext, "suppression")
    end

    # The `data` of `email.scheduled`: the message, plus when it is due.
    class ScheduledData < MessageContext
      # @return [ScheduledContext] the due time and batch.
      def scheduled = block(ScheduledContext, "scheduled")
    end

    # The `data` of `email.failed`: the message, plus why it never went out.
    class FailedData < MessageContext
      # @return [SendFailureContext] the message-level failure.
      def failed = block(SendFailureContext, "failed")
    end

    # The `data` of `email.opened`: the message, plus the open.
    class OpenedData < MessageContext
      # @return [EngagementContext] the open.
      def open = block(EngagementContext, "open")
    end

    # The `data` of `email.clicked`: the message, plus the click.
    class ClickedData < MessageContext
      # @return [ClickContext] the click, including the link.
      def click = block(ClickContext, "click")
    end

    # The `data` of `domain.status`: a sending domain's new state, and its previous one.
    #
    # Not a {MessageContext}: a domain lifecycle event is about the domain, not about a message.
    # `status` and `onboarding_state` are server-controlled strings, not enums.
    class DomainStatusData < Node
      # @return [String] the domain.
      def domain = self["domain"]
      # @return [String] the new status.
      def status = self["status"]
      # @return [String] the new onboarding state.
      def onboarding_state = self["onboarding_state"]
      # @return [DomainStatusPrevious] the state before this change.
      def previous = block(DomainStatusPrevious, "previous")
    end

    # The `data` of `webhook.status`: an endpoint's new state, and its previous one.
    class WebhookStatusData < Node
      # @return [String] the endpoint's URL.
      def endpoint_url = self["endpoint_url"]
      # @return [Boolean] whether the endpoint is now active.
      def active? = self["is_active"]
      # @return [Boolean] whether the endpoint is now deleted.
      def deleted? = self["is_deleted"]
      # @return [String] why the endpoint was disabled.
      def disabled_reason = self["disabled_reason"]
      # @return [WebhookStatusPrevious] the state before this change.
      def previous = block(WebhookStatusPrevious, "previous")
    end
  end
end
