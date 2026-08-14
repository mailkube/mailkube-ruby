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

    it "never writes a recipient address, a subject or a body" do
      Mailkube.enable_logging(device: sink)
      client, = client_with
      client.emails.send(from: "Acme <hello@acme.test>", to: "customer@example.com",
                         subject: "Your receipt", html: "<p>Account balance: 42</p>")

      expect(sink.string).not_to include("customer@example.com")
      expect(sink.string).not_to include("Your receipt")
      expect(sink.string).not_to include("Account balance")
    end

    it "records the request id, so a customer's own logs can be matched to the server's" do
      Mailkube.enable_logging(device: sink)
      client, = client_with(headers: { "x-request-id" => "req_traceable" })
      client.emails.send(**minimal_send)

      expect(sink.string).to include("req_traceable")
    end

    it "omits the request id rather than writing an empty one when the response carried none" do
      Mailkube.enable_logging(device: sink)
      client, = client_with
      client.emails.send(**minimal_send)

      expect(sink.string).not_to include("request_id=")
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

  # MAILKUBE_LOG holds a LEVEL in every mailkube SDK, so presence alone must not turn logging on.
  # Treating it as a flag is not a cosmetic divergence: an operator who sets MAILKUBE_LOG=warning
  # across a fleet is asking for less output and would get the SDK's debug trace instead.
  describe "turning itself on from the environment" do
    it "stays off when MAILKUBE_LOG is unset" do
      expect(described_class.enable_from_env({})).to be_nil
      expect(described_class.device).to be_nil
    end

    it "stays off when MAILKUBE_LOG is set but empty" do
      expect(described_class.enable_from_env({ "MAILKUBE_LOG" => "" })).to be_nil
    end

    ["debug", "trace", "all", "DEBUG", "  debug  "].each do |level|
      it "turns on for MAILKUBE_LOG=#{level.inspect}, a level that admits debug records" do
        expect(described_class.enable_from_env({ "MAILKUBE_LOG" => level })).not_to be_nil
        expect(described_class.device).not_to be_nil
      end
    end

    %w[warning warn error fatal info notice 1 true yes].each do |level|
      it "stays silent for MAILKUBE_LOG=#{level}, which is more selective than debug" do
        expect(described_class.enable_from_env({ "MAILKUBE_LOG" => level })).to be_nil
        expect(described_class.device).to be_nil
      end
    end

    it "leaves logging off for an unrecognized level rather than raising at require time" do
      expect { described_class.enable_from_env({ "MAILKUBE_LOG" => "nonsense" }) }.not_to raise_error
      expect(described_class.device).to be_nil
    end
  end
end
