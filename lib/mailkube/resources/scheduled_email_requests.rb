# frozen_string_literal: true

module Mailkube
  module Resources
    # The request builders for the `scheduled-emails` routes.
    #
    # Standalone builders, one per verb, exactly as the contract requires — and here they earn
    # their keep twice over. Eight verbs across two collections differ only in a path constant and
    # a method string; written inline they would be eight near-identical bodies and the duplication
    # gate would say so. Funnelled through {item} they are one-liners, and the escaping rule is
    # applied in exactly one place.
    module ScheduledEmailRequests
      # The collection path.
      COLLECTION = "scheduled-emails"
      # The batch sub-collection path. Sub-resources mirror sub-paths, so this is a path rather
      # than a suffix bolted onto a verb name.
      BATCHES = "scheduled-emails/batches"

      # The one item request every single-resource verb is built from.
      #
      # @param base [String] the collection path.
      # @param identifier [String] the id or batch label to interpolate.
      # @param method [String] the HTTP method.
      # @param body [Hash, nil] the JSON body, or nil for a body-less request.
      # @return [RequestSpec] the request.
      def self.item(base, identifier, method, body = nil)
        RequestSpec.new(path: "#{base}/#{Serialization.escape_segment(identifier)}", method: method, body: body)
      end
      private_class_method :item

      # Build the listing request.
      #
      # Filters are named here rather than splatted so the five the API supports exist in exactly
      # one place. An omitted filter is dropped by {Serialization.query}, and no filters at all
      # yields no query string rather than a bare `?`.
      #
      # @param status [String, Array<String>, nil] one status, or several.
      # @param batch_id [String, nil] only emails grouped under this batch label.
      # @param scheduled_at_gte [Time, String, nil] only emails due at or after this instant.
      # @param scheduled_at_lte [Time, String, nil] only emails due at or before this instant.
      # @param page [Integer, nil] the 1-based page number.
      # @return [RequestSpec] the listing request.
      def self.list(status: nil, batch_id: nil, scheduled_at_gte: nil, scheduled_at_lte: nil, page: nil)
        filters = { status: status, batch_id: batch_id, scheduled_at_gte: scheduled_at_gte,
                    scheduled_at_lte: scheduled_at_lte, page: page }
        RequestSpec.new(path: COLLECTION, method: "GET", params: Serialization.query(filters))
      end

      # @param url [String] an absolute page link the API issued; it carries its own query.
      # @return [RequestSpec] the request for that page.
      def self.page(url) = RequestSpec.new(path: url, method: "GET")

      # @param email_id [String] the scheduled email's id.
      # @return [RequestSpec] the retrieval request.
      def self.get(email_id) = item(COLLECTION, email_id, "GET")

      # @param email_id [String] the scheduled email's id.
      # @param body [Hash] the new due time, and optionally a batch to move the email into.
      # @return [RequestSpec] the reschedule request.
      def self.update(email_id, body) = item(COLLECTION, email_id, "PATCH", body)

      # @param email_id [String] the scheduled email's id.
      # @return [RequestSpec] the cancellation request.
      def self.cancel(email_id) = item(COLLECTION, email_id, "DELETE")

      # @param batch_id [String] the batch label.
      # @param body [Hash] the new due time. There is deliberately no `batch_id` in it: the batch
      #   is identified by the path, and the server rejects a second one in the body rather than
      #   let it decide which batch actually moves.
      # @return [RequestSpec] the batch reschedule request.
      def self.batch_update(batch_id, body) = item(BATCHES, batch_id, "PATCH", body)

      # @param batch_id [String] the batch label.
      # @return [RequestSpec] the batch cancellation request.
      def self.batch_cancel(batch_id) = item(BATCHES, batch_id, "DELETE")
    end
  end
end
