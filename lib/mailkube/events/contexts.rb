# frozen_string_literal: true

module Mailkube
  module Events
    # The message an event is about: the fields every `email.*` event carries.
    #
    # The shared base of all nine `email.*` payloads, mirroring the server, where one serializer
    # supplies this block to every message event.
    #
    # Every field except the id and timestamp is nullable: they are denormalized from the send
    # transaction, and there is a window in which an event can be emitted before that row exists.
    class MessageContext < Node
      # @return [String] the message's UUID.
      def email_id = self["email_id"]
      # @return [String] when the message was accepted.
      def created_at = self["created_at"]
      # @return [String, nil] the sending domain.
      def domain = self["domain"]
      # @return [String, nil] the subject line.
      def subject = self["subject"]
      # @return [Array<String>, nil] the recipients.
      def to = self["to"]
      # `from` is the wire key and is neither a Ruby keyword nor an Object method, so it needs no
      # renaming — unlike Python, where `from_` is forced.
      # @return [String, nil] the sender address.
      def from = self["from"]

      # Tags stay plain hashes, and {Mailkube::Tag} stays the one **send-side** type.
      #
      # `Tag` is a `Data` with fixed members, so building one here would silently drop an unknown
      # key *inside* a tag — the preservation rule violated three levels down, where nothing on the
      # send side would notice. A second inbound tag class would preserve the keys but cost the SDK
      # family its one-tag-type story. A hash costs neither. The rule: `Tag` is what you construct,
      # a hash is what you read.
      #
      # @return [Array<Hash{String => Object}>] the tags attached at send time, verbatim.
      def tags = self["tags"] || []
    end

    # A single-recipient delivery outcome (`email.delivered`, `email.sent`).
    class DeliveryContext < Node
      # @return [String] the recipient this outcome is about.
      def recipient = self["recipient"]
      # @return [String] when the outcome was recorded.
      def timestamp = self["timestamp"]
    end

    # A delivery failure, carrying the receiving server's verdict.
    #
    # Subclasses {DeliveryContext} because it mirrors the server's own serializer inheritance: a
    # failure *is* a delivery outcome plus a reason.
    class FailureContext < DeliveryContext
      # @return [Integer] the SMTP status code the receiving server returned.
      def code = self["code"]
      # Server-controlled, and deliberately a plain String: a closed set would turn a reason added
      # later into a parse error on an already-released client.
      # @return [String] the failure reason.
      def reason = self["reason"]
    end

    # An open interaction (`email.opened`).
    #
    # These nested keys are camelCase on the wire, unlike every other block here. The SDK mirrors
    # the server rather than normalizing it.
    class EngagementContext < Node
      # @deprecated The platform no longer records it, so a current server omits the key and this
      #   returns nil. Kept rather than removed so code written against an earlier version still
      #   runs, and so an event replayed from an archive still reads.
      # @return [String, nil] the opening client's IP address (wire key `ipAddress`).
      def ip_address = self["ipAddress"]
      # @deprecated As for {#ip_address}.
      # @return [String, nil] the opening client's user agent (wire key `userAgent`).
      def user_agent = self["userAgent"]
      # @return [String] when the interaction was recorded.
      def timestamp = self["timestamp"]
    end

    # A click interaction (`email.clicked`): an open, plus the link that was clicked.
    class ClickContext < EngagementContext
      # @return [String] the clicked URL.
      def link = self["link"]
    end

    # Recipients suppressed for a message (`email.suppressed`).
    class SuppressionContext < Node
      # @return [Array<String>] the suppressed recipients.
      def recipients = self["recipients"]
      # @return [String] when the suppression was applied.
      def timestamp = self["timestamp"]
    end

    # When a scheduled send is due (`email.scheduled`).
    #
    # Unlike the engagement blocks, these keys are snake_case on the wire.
    class ScheduledContext < Node
      # @return [String] when the send is due.
      def scheduled_at = self["scheduled_at"]
      # @return [String, nil] the batch label the send was grouped under.
      def batch_id = self["batch_id"]
    end

    # Why a scheduled send never went out (`email.failed`).
    #
    # Deliberately **not** a {FailureContext}: this is message-level, so there is no recipient and
    # no SMTP code. `reason` stays a plain String for the same reason as everywhere else.
    class SendFailureContext < Node
      # @return [String] why the send failed, e.g. `mta_unreachable`.
      def reason = self["reason"]
      # @return [String] when the failure was recorded.
      def timestamp = self["timestamp"]
    end

    # A sending domain's state before a `domain.status` change.
    class DomainStatusPrevious < Node
      # @return [String] the previous status.
      def status = self["status"]
      # @return [String] the previous onboarding state.
      def onboarding_state = self["onboarding_state"]
    end

    # A webhook endpoint's state before a `webhook.status` change.
    class WebhookStatusPrevious < Node
      # Spelled `active?` rather than `is_active`: Ruby's predicate convention. The wire key stays
      # `is_active`, and {Node#[]} reaches it under that name.
      # @return [Boolean] whether the endpoint was active.
      def active? = self["is_active"]
      # @return [Boolean] whether the endpoint was deleted.
      def deleted? = self["is_deleted"]
      # @return [String] why the endpoint was disabled, e.g. `none`, `user`, `low_quality`.
      def disabled_reason = self["disabled_reason"]
    end
  end
end
