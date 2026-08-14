# frozen_string_literal: true

module Mailkube
  # A file attached to an email.
  #
  # `content` is the raw bytes; the SDK base64-encodes them for the wire. `content_type` is
  # inferred from the filename when omitted.
  class Attachment < Data.define(:filename, :content, :content_type)
    # @param filename [String] the name of the attached file.
    # @param content [String] the raw file content.
    # @param content_type [String, nil] the MIME type, inferred from the filename when nil.
    def initialize(filename:, content:, content_type: nil) = super
  end

  # A free-form name/value tag attached to an outgoing email.
  #
  # Tags are forwarded to the server, which denormalizes them onto the sending log so you can
  # filter, export and dashboard sends by tag, and so they ride along on delivery webhooks. Tag
  # values are not encrypted, so do not put personal data in them.
  class Tag < Data.define(:name, :value)
    # @param name [String] the tag name.
    # @param value [String] the tag value; it may be empty.
    def initialize(name:, value: "") = super
  end

  # The result of a successful send.
  #
  # A **scheduled** send (one carrying `scheduled_at`) is acknowledged with 202 and a richer
  # body; `status`, `scheduled_at` and `batch_id` are populated only then, and `#scheduled?` is
  # the discriminator. An immediate send leaves all three nil.
  #
  # This is the worked example of the contract's **widen, never union** rule: one call can return
  # two shapes, and adding optional fields plus a predicate keeps every existing caller valid,
  # where returning one of two classes would not.
  #
  # Timestamps stay the verbatim ISO-8601 strings the server sent. The SDK does not validate or
  # reinterpret server data; call `Time.iso8601` yourself if you want an object. Transport
  # metadata (response headers, the request id) belongs on the exception, not here.
  class Email < Data.define(:id, :message_id, :idempotent_replayed, :status, :scheduled_at, :batch_id)
    # @param id [String] the accepted message's UUID.
    # @param message_id [String, nil] the RFC Message-ID, when the deployment returns one.
    # @param idempotent_replayed [Boolean] true when this replays an earlier identical request.
    # @param status [String, nil] the scheduled email's status, on a scheduled ack only.
    # @param scheduled_at [String, nil] when the send is due, on a scheduled ack only.
    # @param batch_id [String, nil] the batch label the send was grouped under.
    def initialize(id:, message_id: nil, idempotent_replayed: false, status: nil, scheduled_at: nil,
                   batch_id: nil)
      super
    end

    # @return [Boolean] true when the send was accepted for later delivery rather than sent now.
    def scheduled? = !scheduled_at.nil?
  end
end
