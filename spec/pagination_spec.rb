# frozen_string_literal: true

require_relative "support/sequence_adapter"

# Pagination is its own contract concern: a page model, and an iterator that advances by following
# the server's link rather than by counting. What a listing puts on the wire is in
# `scheduled_emails_spec.rb`.
RSpec.describe "paging through a listing" do
  let(:base) { Mailkube::DEFAULT_BASE_URL }

  # @param next_link [String, nil] the link to the following page, omitted when there is none.
  # @param ids [Array<String>] the record ids on this page.
  def page_body(ids, next_link: nil)
    steps = next_link.nil? ? {} : { "next" => next_link }
    { "pagination" => { "steps" => steps, "total_count" => 3, "current_page" => 1 },
      "data" => ids.map { |id| { "id" => id } } }
  end

  # @return [Array(Mailkube::Client, SpecHelpers::SequenceAdapter)] a client over a page sequence.
  def client_over(*bodies)
    adapter = SpecHelpers::SequenceAdapter.new(*bodies)
    [Mailkube::Client.new(api_key: "mk_test", http: adapter), adapter]
  end

  describe "the page model" do
    it "reports more pages when the server issued a next link" do
      client, = client_over(page_body(%w[e1], next_link: "#{Mailkube::DEFAULT_BASE_URL}scheduled-emails?page=2"))

      expect(client.scheduled_emails.list).to be_more
    end

    it "reports no more pages when the step is absent, which is how the server says 'the end'" do
      client, = client_over(page_body(%w[e1]))

      expect(client.scheduled_emails.list).not_to be_more
    end
  end

  describe "iterating every page" do
    it "follows the server's next link rather than incrementing a page counter" do
      client, adapter = client_over(page_body(%w[e1], next_link: "#{base}scheduled-emails?cursor=opaque"),
                                    page_body(%w[e2]))
      client.scheduled_emails.iter_all.to_a

      expect(adapter.calls.map { |call| call[:url] })
        .to eq(["#{base}scheduled-emails", "#{base}scheduled-emails?cursor=opaque"])
    end

    it "yields every record across every page, in order" do
      client, = client_over(page_body(%w[e1 e2], next_link: "#{base}scheduled-emails?page=2"),
                            page_body(%w[e3]))

      expect(client.scheduled_emails.iter_all.map(&:id)).to eq(%w[e1 e2 e3])
    end

    it "stops after a single page when there is no next link" do
      client, adapter = client_over(page_body(%w[e1]))
      client.scheduled_emails.iter_all.to_a

      expect(adapter.calls.size).to eq(1)
    end

    it "serializes the caller's filters once, onto the first request only" do
      client, adapter = client_over(page_body(%w[e1], next_link: "#{base}scheduled-emails?page=2"),
                                    page_body(%w[e2]))
      client.scheduled_emails.iter_all(status: "scheduled").to_a

      expect(adapter.calls.first[:url]).to include("status=scheduled")
      expect(adapter.calls.last[:url]).to eq("#{base}scheduled-emails?page=2")
    end

    it "makes no request at all until it is iterated" do
      client, adapter = client_over(page_body(%w[e1]))
      client.scheduled_emails.iter_all

      expect(adapter.calls).to be_empty
    end

    it "costs nothing to abandon early: the page after the one in hand is never fetched" do
      client, adapter = client_over(page_body(%w[e1 e2], next_link: "#{base}scheduled-emails?page=2"))

      expect(client.scheduled_emails.iter_all.first).to have_attributes(id: "e1")
      expect(adapter.calls.size).to eq(1)
    end

    it "refuses a next link on another origin rather than handing a foreign host the API key" do
      client, = client_over(page_body(%w[e1], next_link: "https://evil.example/scheduled-emails?page=2"))

      expect { client.scheduled_emails.iter_all.to_a }
        .to raise_error(Mailkube::ConfigurationError, /not on the configured API origin/)
    end
  end
end
