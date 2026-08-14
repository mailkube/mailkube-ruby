# frozen_string_literal: true

require "stringio"

# Logging is opt-in, and the contract's requirement on it is negative: whatever else it writes, it
# must never write the API key or an idempotency key. So these examples assert on what is absent
# and on the mask, never on the line's shape — a format nobody promised is a format nobody has to
# keep stable.
RSpec.describe Mailkube::Logging do
  after { described_class.disable! }

  describe "silent by default" do
    it "writes nothing at all until logging is enabled" do
      sink = StringIO.new
      client, = client_with
      client.emails.send(**minimal_send)

      expect(sink.string).to be_empty
      expect(described_class.device).to be_nil
    end
  end

  describe "once enabled" do
    let(:sink) { StringIO.new }

    it "records the request and the response" do
      Mailkube.enable_logging(device: sink)
      client, = client_with
      client.emails.send(**minimal_send)

      expect(sink.string).to include("POST", "#{Mailkube::DEFAULT_BASE_URL}emails")
      expect(sink.string).to include("200")
    end

    it "never writes the API key or the idempotency key" do
      Mailkube.enable_logging(device: sink)
      client, = client_with
      client.emails.send(**minimal_send, idempotency_key: "key-1")

      expect(sink.string).not_to include("mk_test")
      expect(sink.string).not_to include("key-1")
      expect(sink.string).to include(described_class::REDACTION)
    end

    it "goes quiet again when logging is turned off" do
      Mailkube.enable_logging(device: sink)
      described_class.disable!
      client, = client_with
      client.emails.send(**minimal_send)

      expect(sink.string).to be_empty
    end
  end

  describe "redaction" do
    it "masks the secret headers and keeps the rest" do
      redacted = described_class.redact("Authorization" => "Bearer mk_test", "Idempotency-Key" => "k",
                                        "X-Trace" => "keep-me")

      expect(redacted).to eq("Authorization" => "***", "Idempotency-Key" => "***", "X-Trace" => "keep-me")
    end

    it "matches header names case-insensitively, as HTTP requires" do
      expect(described_class.redact("authorization" => "Bearer mk_test")).to eq("authorization" => "***")
    end

    it "does not modify the headers the transport is about to send" do
      headers = { "Authorization" => "Bearer mk_test" }
      described_class.redact(headers)

      expect(headers).to eq("Authorization" => "Bearer mk_test")
    end
  end

  describe "turning itself on from the environment" do
    it "stays off when MAILKUBE_LOG is unset" do
      expect(described_class.enable_from_env({})).to be_nil
      expect(described_class.device).to be_nil
    end

    it "stays off when MAILKUBE_LOG is set but empty" do
      expect(described_class.enable_from_env({ "MAILKUBE_LOG" => "" })).to be_nil
    end

    it "turns on for any non-empty value, because there is only one class of record to filter" do
      expect(described_class.enable_from_env({ "MAILKUBE_LOG" => "debug" })).not_to be_nil
      expect(described_class.device).not_to be_nil
    end
  end
end
