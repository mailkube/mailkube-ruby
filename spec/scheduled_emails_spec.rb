# frozen_string_literal: true

# The scheduled-email verbs: what each one puts on the wire, and what it makes of the answer.
# Page-following lives in `pagination_spec.rb`, which is its own contract concern.
RSpec.describe Mailkube::Resources::ScheduledEmails do
  let(:base) { Mailkube::DEFAULT_BASE_URL }

  describe "listing" do
    it "sends no query string at all when nothing is filtered" do
      client, adapter = client_with(body: { "data" => [] })
      client.scheduled_emails.list

      expect(adapter.calls.first).to include(method: "GET", url: "#{base}scheduled-emails")
    end

    it "joins several statuses into one parameter rather than repeating the parameter" do
      client, adapter = client_with(body: { "data" => [] })
      client.scheduled_emails.list(status: %w[scheduled canceled])

      expect(adapter.calls.first[:url]).to eq("#{base}scheduled-emails?status=scheduled%2Ccanceled")
    end

    it "sends every filter the API supports, including both scheduling bounds" do
      client, adapter = client_with(body: { "data" => [] })
      client.scheduled_emails.list(status: "scheduled", batch_id: "b1", page: 2,
                                   scheduled_at_gte: Time.utc(2026, 8, 1, 7),
                                   scheduled_at_lte: "2026-08-31T07:00:00Z")

      expect(adapter.calls.first[:url]).to include("status=scheduled", "batch_id=b1", "page=2",
                                                   "scheduled_at_gte=2026-08-01T07%3A00%3A00Z",
                                                   "scheduled_at_lte=2026-08-31T07%3A00%3A00Z")
    end

    it "omits a filter the caller did not set rather than sending it empty" do
      client, adapter = client_with(body: { "data" => [] })
      client.scheduled_emails.list(status: "scheduled")

      expect(adapter.calls.first[:url]).not_to include("batch_id", "page")
    end

    it "parses the records, keeping recipients as the server's summary string" do
      client, = client_with(body: { "data" => [{ "id" => "e1", "status" => "scheduled",
                                                 "recipients" => "a@b.com +2", "subject" => "Hi" }] })
      email = client.scheduled_emails.list.data.first

      expect(email).to have_attributes(id: "e1", status: "scheduled", recipients: "a@b.com +2", subject: "Hi")
    end

    it "defaults every field the server omitted, so a lean page never raises" do
      client, = client_with(body: { "data" => [{ "id" => "e1" }] })
      email = client.scheduled_emails.list.data.first

      expect(email).to have_attributes(object: "scheduled_email", status: "", tags: [], batch_id: nil)
    end
  end

  describe "retrieving one" do
    it "requests the item path" do
      client, adapter = client_with(body: { "id" => "e1" })
      client.scheduled_emails.get("e1")

      expect(adapter.calls.first).to include(method: "GET", url: "#{base}scheduled-emails/e1")
    end

    it "escapes the identifier, so an id carrying a separator cannot re-target the request" do
      client, adapter = client_with(body: { "id" => "e1" })
      client.scheduled_emails.get("../batches/x?page=9")

      expect(adapter.calls.first[:url]).to eq("#{base}scheduled-emails/..%2Fbatches%2Fx%3Fpage%3D9")
    end
  end

  describe "rescheduling one" do
    it "PATCHes the new due time, rendering a Time as ISO-8601" do
      client, adapter = client_with(body: { "id" => "e1" })
      client.scheduled_emails.update("e1", scheduled_at: Time.utc(2026, 8, 21, 7))

      expect(adapter.calls.first).to include(method: "PATCH", body: { "scheduled_at" => "2026-08-21T07:00:00Z" })
    end

    it "includes a batch only when the caller is moving the email into one" do
      client, adapter = client_with(body: { "id" => "e1" })
      client.scheduled_emails.update("e1", scheduled_at: "2026-08-21T07:00:00Z", batch_id: "b1")

      expect(adapter.calls.first[:body]).to eq("scheduled_at" => "2026-08-21T07:00:00Z", "batch_id" => "b1")
    end
  end

  describe "cancelling one" do
    it "DELETEs the item and reports the cancellation" do
      client, adapter = client_with(body: { "id" => "e1", "object" => "scheduled_email", "status" => "canceled" })
      result = client.scheduled_emails.cancel("e1")

      expect(adapter.calls.first).to include(method: "DELETE", url: "#{base}scheduled-emails/e1")
      expect(result).to have_attributes(id: "e1", status: "canceled")
    end
  end

  describe "batches" do
    it "PATCHes only the due time, because the path already names the batch" do
      client, adapter = client_with(body: { "batch_id" => "b1", "rescheduled_count" => 40 })
      client.scheduled_emails.batches.update("b1", scheduled_at: "2026-08-22T07:00:00Z")

      expect(adapter.calls.first).to include(method: "PATCH", url: "#{base}scheduled-emails/batches/b1")
      expect(adapter.calls.first[:body]).to eq("scheduled_at" => "2026-08-22T07:00:00Z")
    end

    it "reports how many emails a reschedule moved" do
      client, = client_with(body: { "batch_id" => "b1", "rescheduled_count" => 40,
                                    "scheduled_at" => "2026-08-22T07:00:00Z" })

      expect(client.scheduled_emails.batches.update("b1", scheduled_at: "2026-08-22T07:00:00Z"))
        .to have_attributes(batch_id: "b1", rescheduled_count: 40, scheduled_at: "2026-08-22T07:00:00Z")
    end

    it "DELETEs the batch and reports how many emails were cancelled" do
      client, adapter = client_with(body: { "batch_id" => "b1", "canceled_count" => 40 })
      result = client.scheduled_emails.batches.cancel("b1")

      expect(adapter.calls.first).to include(method: "DELETE", url: "#{base}scheduled-emails/batches/b1")
      expect(result).to have_attributes(batch_id: "b1", canceled_count: 40)
    end

    it "treats an unknown batch as a no-op reporting zero, which is not an error" do
      client, = client_with(body: { "object" => "scheduled_email.batch", "batch_id" => "nope",
                                    "canceled_count" => 0 })

      expect(client.scheduled_emails.batches.cancel("nope").canceled_count).to eq(0)
    end
  end

  describe "the errors this surface adds" do
    it "maps an unknown id to NotFoundError, carrying the server's name" do
      client, = client_with(status: 404, body: { "name" => "scheduled_email_not_found",
                                                 "message" => "No such scheduled email." })

      expect { client.scheduled_emails.get("nope") }.to raise_error(Mailkube::NotFoundError) do |error|
        expect(error.error_name).to eq(Mailkube::ErrorName::SCHEDULED_EMAIL_NOT_FOUND)
      end
    end

    it "maps a plan without scheduling to AuthenticationError" do
      client, = client_with(status: 403, body: { "name" => "scheduling_not_included" })

      expect { client.scheduled_emails.list }.to raise_error(Mailkube::AuthenticationError) do |error|
        expect(error.error_name).to eq(Mailkube::ErrorName::SCHEDULING_NOT_INCLUDED)
      end
    end

    it "maps an email that is no longer pending to InvalidRequestError" do
      client, = client_with(status: 422, body: { "name" => "scheduled_email_not_pending" })

      expect { client.scheduled_emails.cancel("e1") }.to raise_error(Mailkube::InvalidRequestError) do |error|
        expect(error.error_name).to eq(Mailkube::ErrorName::SCHEDULED_EMAIL_NOT_PENDING)
      end
    end
  end
end
