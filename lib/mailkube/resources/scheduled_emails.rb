# frozen_string_literal: true

module Mailkube
  module Resources
    # Batch operations, reached as `client.scheduled_emails.batches`.
    #
    # A sibling resource sharing the enclosing namespace's transport, not a method group: the wire
    # has a `scheduled-emails/batches/{id}` sub-path, so the SDK has a sub-namespace. A
    # `update_batch` suffix would flatten a structure the API actually has.
    class ScheduledEmailBatches
      # @param transport [#request_json] the transport performing this resource's requests.
      def initialize(transport)
        @transport = transport
        freeze
      end

      # Reschedule every pending email in a batch.
      #
      # @param batch_id [String] the batch label.
      # @param scheduled_at [Time, String] the new due time, in the future and within the plan's
      #   scheduling horizon. ISO-8601 with an offset, or a Time.
      # @return [ScheduledEmailBatchUpdate] how many emails moved, and where to.
      # @raise [APIError] on any non-2xx response.
      def update(batch_id, scheduled_at:)
        body = { "scheduled_at" => Serialization.to_iso(scheduled_at) }
        ScheduledEmailBatchUpdate.from(@transport.request_json(ScheduledEmailRequests.batch_update(batch_id, body)))
      end

      # Cancel every pending email in a batch.
      #
      # An unknown batch is a no-op reporting a count of 0 rather than a 404, so a count of 0 is
      # not a failure.
      #
      # @param batch_id [String] the batch label.
      # @return [ScheduledEmailBatchCancel] how many emails were cancelled.
      # @raise [APIError] on any non-2xx response.
      def cancel(batch_id)
        ScheduledEmailBatchCancel.from(@transport.request_json(ScheduledEmailRequests.batch_cancel(batch_id)))
      end
    end

    # The `scheduled_emails` namespace, reached as `client.scheduled_emails`.
    #
    # Sends made with `scheduled_at:` are manageable here until they are due. A sent email has left
    # the collection, so `status: "sent"` is a validation error rather than an empty result.
    class ScheduledEmails
      # @return [ScheduledEmailBatches] the batch operations.
      attr_reader :batches

      # @param transport [#request_json] the transport performing this resource's requests.
      def initialize(transport)
        @transport = transport
        @batches = ScheduledEmailBatches.new(transport)
        freeze
      end

      # List one page of scheduled emails.
      #
      # Every filter is optional and an omitted one never reaches the wire. A list of statuses
      # becomes one comma-joined parameter rather than a repeated one. The listing is scoped
      # server-side to a rolling window around now, so a bound in the direction that can never
      # match is rejected rather than silently returning nothing.
      #
      # @param status [String, Array<String>, nil] one status, or several. Only `scheduled`,
      #   `canceled` and `failed` can be listed.
      # @param batch_id [String, nil] only emails grouped under this batch label.
      # @param scheduled_at_gte [Time, String, nil] only emails due at or after this instant.
      # @param scheduled_at_lte [Time, String, nil] only emails due at or before this instant.
      # @param page [Integer, nil] the 1-based page number to fetch.
      # @return [ScheduledEmailPage] one page, plus its pagination block.
      # @raise [APIError] on any non-2xx response.
      def list(status: nil, batch_id: nil, scheduled_at_gte: nil, scheduled_at_lte: nil, page: nil)
        fetch_page(ScheduledEmailRequests.list(status: status, batch_id: batch_id,
                                               scheduled_at_gte: scheduled_at_gte,
                                               scheduled_at_lte: scheduled_at_lte, page: page))
      end

      # Iterate every scheduled email matching the filters, across every page.
      #
      # Lazy: no request is made until the enumerator is iterated, and abandoning it early costs
      # nothing. Pages advance by **following the server's `next` link**, never by incrementing a
      # counter, so the server stays free to change its pagination scheme. The link is fetched
      # through {Config#build_url}, which refuses one off the configured origin — every request
      # carries the API key, so a link naming a foreign host must not be followed.
      #
      # @param (see #list)
      # @return [Enumerator<ScheduledEmail>] every matching scheduled email, page after page.
      def iter_all(status: nil, batch_id: nil, scheduled_at_gte: nil, scheduled_at_lte: nil, page: nil)
        Enumerator.new do |yielder|
          current = list(status: status, batch_id: batch_id, scheduled_at_gte: scheduled_at_gte,
                         scheduled_at_lte: scheduled_at_lte, page: page)
          loop do
            current.data.each { |item| yielder << item }
            link = current.pagination.steps.next
            break if link.nil?

            current = fetch_page(ScheduledEmailRequests.page(link))
          end
        end
      end

      # Retrieve one scheduled email.
      #
      # @param email_id [String] the id the scheduled-send acknowledgement returned.
      # @return [ScheduledEmail] the scheduled email.
      # @raise [NotFoundError] when no such scheduled email exists, which is also what an id
      #   belonging to another organization reports.
      def get(email_id)
        ScheduledEmail.from(@transport.request_json(ScheduledEmailRequests.get(email_id)))
      end

      # Reschedule one scheduled email, optionally moving it into or out of a batch.
      #
      # The content of a scheduled email is immutable; only its due time and batch can change.
      #
      # @param email_id [String] the id the scheduled-send acknowledgement returned.
      # @param scheduled_at [Time, String] the new due time.
      # @param batch_id [String, nil] a batch to move the email into.
      # @return [ScheduledEmail] the rescheduled email.
      # @raise [InvalidRequestError] when the email is no longer pending.
      def update(email_id, scheduled_at:, batch_id: nil)
        body = { "scheduled_at" => Serialization.to_iso(scheduled_at), "batch_id" => batch_id }.compact
        ScheduledEmail.from(@transport.request_json(ScheduledEmailRequests.update(email_id, body)))
      end

      # Cancel one scheduled email before it is sent.
      #
      # @param email_id [String] the id the scheduled-send acknowledgement returned.
      # @return [CanceledScheduledEmail] the cancellation acknowledgement.
      # @raise [InvalidRequestError] when the email is no longer pending.
      def cancel(email_id)
        CanceledScheduledEmail.from(@transport.request_json(ScheduledEmailRequests.cancel(email_id)))
      end

      private

      # @param spec [RequestSpec] the page request.
      # @return [ScheduledEmailPage] the parsed page.
      def fetch_page(spec) = ScheduledEmailPage.from(@transport.request_json(spec))
    end
  end
end
