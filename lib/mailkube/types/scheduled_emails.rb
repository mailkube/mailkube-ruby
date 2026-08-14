# frozen_string_literal: true

module Mailkube
  # One scheduled email, as the `scheduled-emails` collection reports it.
  #
  # Richer than the {Email} acknowledgement a scheduled send returns: that ack is lean by design,
  # and these are the fields you get by asking the collection for the email afterwards.
  #
  # Timestamps stay the verbatim ISO-8601 strings the server sent; call `Time.iso8601` yourself if
  # you want objects. `tags` are plain hashes rather than {Tag} values — see {Events::Node} for the
  # rule: {Tag} is what you construct, a hash is what you read.
  class ScheduledEmail < Data.define(:id, :message_id, :object, :status, :scheduled_at, :created_at,
                                     :batch_id, :subject, :recipients, :topic, :tags)
    # @param id [String] the scheduled email's UUID.
    # @param message_id [String, nil] the RFC Message-ID.
    # @param object [String] the resource discriminator, always `scheduled_email`.
    # @param status [String] one of `scheduled`, `canceled`, `sent`, `failed`. A server-controlled
    #   string, deliberately not an enum: a value added later must not break a released client.
    # @param scheduled_at [String, nil] when the send is due.
    # @param created_at [String, nil] when the send was accepted.
    # @param batch_id [String, nil] the batch label this send was grouped under.
    # @param subject [String, nil] the subject line.
    # @param recipients [String, nil] a recipient **summary**, not a list: `"a@b.com +2"` when
    #   there are more, the bare address when there is one, `""` when there are none. The full
    #   list stays server-side.
    # @param topic [String, nil] the mailing-list topic slug.
    # @param tags [Array<Hash{String => Object}>] the tags attached at send time, verbatim.
    def initialize(id:, message_id: nil, object: "scheduled_email", status: "", scheduled_at: nil,
                   created_at: nil, batch_id: nil, subject: nil, recipients: nil, topic: nil, tags: [])
      super
    end

    # @param payload [Hash{String => Object}] one decoded `scheduled_email` object.
    # @return [ScheduledEmail] the model.
    def self.from(payload)
      new(id: payload["id"], message_id: payload["message_id"],
          object: payload["object"] || "scheduled_email", status: payload["status"] || "",
          scheduled_at: payload["scheduled_at"], created_at: payload["created_at"],
          batch_id: payload["batch_id"], subject: payload["subject"],
          recipients: payload["recipients"], topic: payload["topic"], tags: payload["tags"] || [])
    end
  end

  # Links to the pages adjacent to the one in hand.
  #
  # The server **omits** a step at either end of the range rather than sending null, so an absent
  # link and a nil value mean the same thing: there is no such page.
  class PageSteps < Data.define(:next, :previous)
    # @param next [String, nil] absolute URL of the following page, nil on the last page.
    # @param previous [String, nil] absolute URL of the preceding page, nil on the first page.
    def initialize(next: nil, previous: nil) = super

    # @param payload [Hash{String => Object}, nil] the decoded `steps` block, which may be absent.
    # @return [PageSteps] the model.
    def self.from(payload) = new(next: (payload || {})["next"], previous: (payload || {})["previous"])
  end

  # The pagination block that accompanies every listing.
  #
  # Every member has a default because the server adds `total_count` and `current_page`
  # conditionally, exactly as it does the step links.
  class Pagination < Data.define(:steps, :total_count, :current_page)
    # @param steps [PageSteps] links to the adjacent pages.
    # @param total_count [Integer] matching records across every page.
    # @param current_page [Integer] the 1-based number of the page in hand.
    def initialize(steps: PageSteps.new, total_count: 0, current_page: 1) = super

    # @param payload [Hash{String => Object}, nil] the decoded `pagination` block.
    # @return [Pagination] the model.
    def self.from(payload)
      block = payload || {}
      new(steps: PageSteps.from(block["steps"]), total_count: block["total_count"] || 0,
          current_page: block["current_page"] || 1)
    end
  end

  # One page of scheduled emails: the records, plus how to reach the neighbouring pages.
  class ScheduledEmailPage < Data.define(:pagination, :data)
    # @param pagination [Pagination] page metadata, including the adjacent-page links.
    # @param data [Array<ScheduledEmail>] the scheduled emails on this page.
    def initialize(pagination: Pagination.new, data: []) = super

    # @param payload [Hash{String => Object}] the decoded listing body.
    # @return [ScheduledEmailPage] the model.
    def self.from(payload)
      new(pagination: Pagination.from(payload["pagination"]),
          data: (payload["data"] || []).map { |item| ScheduledEmail.from(item) })
    end

    # Spelled `more?` rather than `has_more`: Ruby's predicate convention, and the same call this
    # gem already makes for `Email#scheduled?` where the other SDKs say `is_scheduled`.
    #
    # @return [Boolean] true when the server issued a link to a following page.
    def more? = !pagination.steps.next.nil?
  end
end
