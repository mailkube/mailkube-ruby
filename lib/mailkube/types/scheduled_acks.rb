# frozen_string_literal: true

module Mailkube
  # What a cancellation reports back.
  #
  # A separate model from {ScheduledEmail} rather than a widened one: the server answers a
  # cancellation with a three-field acknowledgement, not with the record, and a model mirrors the
  # wire and nothing else.
  class CanceledScheduledEmail < Data.define(:id, :object, :status)
    # @param id [String] the canceled scheduled email's UUID.
    # @param object [String] the resource discriminator, always `scheduled_email`.
    # @param status [String] the resulting status, always `canceled`.
    def initialize(id:, object: "scheduled_email", status: "canceled") = super

    # @param payload [Hash{String => Object}] the decoded acknowledgement.
    # @return [CanceledScheduledEmail] the model.
    def self.from(payload)
      new(id: payload["id"], object: payload["object"] || "scheduled_email",
          status: payload["status"] || "canceled")
    end
  end

  # What cancelling a whole batch reports back.
  class ScheduledEmailBatchCancel < Data.define(:object, :batch_id, :canceled_count)
    # @param object [String] the resource discriminator, always `scheduled_email.batch`.
    # @param batch_id [String] the batch that was targeted.
    # @param canceled_count [Integer] how many pending emails the cancellation affected. An
    #   unknown batch is a no-op reporting 0, **not** an error, so do not treat 0 as a failure.
    def initialize(object: "scheduled_email.batch", batch_id: "", canceled_count: 0) = super

    # @param payload [Hash{String => Object}] the decoded acknowledgement.
    # @return [ScheduledEmailBatchCancel] the model.
    def self.from(payload)
      new(object: payload["object"] || "scheduled_email.batch", batch_id: payload["batch_id"] || "",
          canceled_count: payload["canceled_count"] || 0)
    end
  end

  # What rescheduling a whole batch reports back.
  class ScheduledEmailBatchUpdate < Data.define(:object, :batch_id, :rescheduled_count, :scheduled_at)
    # @param object [String] the resource discriminator, always `scheduled_email.batch`.
    # @param batch_id [String] the batch that was targeted.
    # @param rescheduled_count [Integer] how many pending emails moved. An unknown batch is a
    #   no-op reporting 0, **not** an error.
    # @param scheduled_at [String, nil] the new due time applied to every moved email.
    def initialize(object: "scheduled_email.batch", batch_id: "", rescheduled_count: 0, scheduled_at: nil)
      super
    end

    # @param payload [Hash{String => Object}] the decoded acknowledgement.
    # @return [ScheduledEmailBatchUpdate] the model.
    def self.from(payload)
      new(object: payload["object"] || "scheduled_email.batch", batch_id: payload["batch_id"] || "",
          rescheduled_count: payload["rescheduled_count"] || 0, scheduled_at: payload["scheduled_at"])
    end
  end
end
