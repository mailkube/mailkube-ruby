# frozen_string_literal: true

RSpec.describe Mailkube::Resources::Emails do
  it "POSTs to the emails path with the required fields" do
    client, adapter = client_with
    client.emails.send(**minimal_send, html: "<p>Hi</p>")

    call = adapter.calls.first
    expect(call[:method]).to eq("POST")
    expect(call[:url]).to end_with("emails")
    expect(call[:body]).to eq("from" => "a@x.com", "to" => "b@y.com", "subject" => "Hi", "html" => "<p>Hi</p>")
  end

  it "omits unset fields entirely rather than sending them as null" do
    client, adapter = client_with
    client.emails.send(**minimal_send)

    expect(adapter.calls.first[:body].keys).to contain_exactly("from", "to", "subject")
  end

  it "lifts the idempotency key into a header, not the body" do
    client, adapter = client_with
    client.emails.send(**minimal_send, idempotency_key: "key-1")

    call = adapter.calls.first
    expect(call[:headers]).to include("Idempotency-Key" => "key-1")
    expect(call[:body]).not_to have_key("idempotency_key")
  end

  it "base64-encodes attachment content" do
    client, adapter = client_with
    attachment = Mailkube::Attachment.new(filename: "a.txt", content: "hello", content_type: "text/plain")
    client.emails.send(**minimal_send, attachments: [attachment])

    expect(adapter.calls.first[:body]["attachments"]).to eq(
      [{ "filename" => "a.txt", "content" => "aGVsbG8=", "content_type" => "text/plain" }]
    )
  end

  it "sends tags as name/value pairs, defaulting the value to empty" do
    client, adapter = client_with
    client.emails.send(**minimal_send, tags: [Mailkube::Tag.new(name: "campaign")])

    expect(adapter.calls.first[:body]["tags"]).to eq([{ "name" => "campaign", "value" => "" }])
  end

  it "treats empty collections as absent rather than sending empty arrays" do
    client, adapter = client_with
    client.emails.send(**minimal_send, attachments: [], tags: [])

    expect(adapter.calls.first[:body].keys).to contain_exactly("from", "to", "subject")
  end

  it "renders a Time as ISO-8601 and passes a string through untouched" do
    client, adapter = client_with
    client.emails.send(**minimal_send, scheduled_at: Time.utc(2026, 1, 2, 3, 4, 5))
    client.emails.send(**minimal_send, scheduled_at: "2026-01-02T03:04:05Z")

    expect(adapter.calls.map { |call| call[:body]["scheduled_at"] })
      .to eq(["2026-01-02T03:04:05Z", "2026-01-02T03:04:05Z"])
  end

  describe "the response model" do
    it "reports an immediate send as not scheduled" do
      client, = client_with(body: { "id" => "abc123", "message_id" => "<abc@msg>" })
      email = client.emails.send(**minimal_send)

      expect(email).to have_attributes(id: "abc123", message_id: "<abc@msg>", scheduled?: false)
    end

    it "widens into the scheduled shape rather than returning a different type" do
      client, = client_with(body: { "id" => "abc", "status" => "scheduled", "scheduled_at" => "2026-01-02T03:04:05Z",
                                    "batch_id" => "batch-1" })
      email = client.emails.send(**minimal_send, scheduled_at: "2026-01-02T03:04:05Z")

      expect(email).to have_attributes(scheduled?: true, status: "scheduled", batch_id: "batch-1")
    end

    it "reports an idempotent replay from the response header" do
      client, = client_with(headers: { "idempotent-replayed" => "true" })
      email = client.emails.send(**minimal_send, idempotency_key: "key-1")

      expect(email.idempotent_replayed).to be(true)
    end

    it "ignores fields this release has never heard of" do
      client, = client_with(body: { "id" => "abc", "invented_next_year" => 42 })

      expect(client.emails.send(**minimal_send).id).to eq("abc")
    end

    it "raises when a 2xx body carries no id" do
      client, = client_with(body: {})

      expect { client.emails.send(**minimal_send) }
        .to raise_error(Mailkube::APIError, /expected a JSON body with an 'id'/)
    end
  end
end
