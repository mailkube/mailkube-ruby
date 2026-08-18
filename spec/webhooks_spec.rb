# frozen_string_literal: true

require "openssl"
require "time"

require_relative "support/rack_style_headers"

RSpec.describe Mailkube::Webhooks do
  let(:secret) { "whsec_test" }
  let(:payload) { '{"type":"email.delivered","data":{"id":"abc"}}' }
  let(:id) { "evt_1" }

  # Computes the HMAC directly rather than calling `.sign`: this is the oracle every example
  # verifies against, so it must not share an implementation with the code under test.
  def headers_for(payload:, id:, timestamp:, secret:)
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{id}.#{timestamp}.#{payload}")
    { "X-Webhook-Id" => id, "X-Webhook-Ts" => timestamp, "X-Webhook-Sig" => "sha256=#{digest}" }
  end

  it "returns the payload when the signature and timestamp are good" do
    headers = headers_for(payload: payload, id: id, timestamp: Time.now.utc.iso8601, secret: secret)

    expect(described_class.verify_signature(payload: payload, headers: headers, secret: secret)).to eq(payload)
  end

  it "matches header names case-insensitively, as HTTP requires" do
    signed = headers_for(payload: payload, id: id, timestamp: Time.now.utc.iso8601, secret: secret)
    headers = signed.transform_keys(&:downcase)

    expect(described_class.verify_signature(payload: payload, headers: headers, secret: secret)).to eq(payload)
  end

  it "rejects a signature made with a different secret" do
    headers = headers_for(payload: payload, id: id, timestamp: Time.now.utc.iso8601, secret: "wrong")

    expect { described_class.verify_signature(payload: payload, headers: headers, secret: secret) }
      .to raise_error(Mailkube::SignatureVerificationError, /signature mismatch/)
  end

  it "rejects a body altered after signing" do
    headers = headers_for(payload: payload, id: id, timestamp: Time.now.utc.iso8601, secret: secret)

    expect { described_class.verify_signature(payload: "#{payload} ", headers: headers, secret: secret) }
      .to raise_error(Mailkube::SignatureVerificationError)
  end

  it "rejects a timestamp outside the freshness window" do
    stale = (Time.now.utc - 3600).iso8601
    headers = headers_for(payload: payload, id: id, timestamp: stale, secret: secret)

    expect { described_class.verify_signature(payload: payload, headers: headers, secret: secret) }
      .to raise_error(Mailkube::SignatureVerificationError, /freshness window/)
  end

  it "accepts a stale timestamp when the caller widens the tolerance" do
    stale = (Time.now.utc - 3600).iso8601
    headers = headers_for(payload: payload, id: id, timestamp: stale, secret: secret)

    expect(described_class.verify_signature(payload: payload, headers: headers, secret: secret, tolerance: 7200))
      .to eq(payload)
  end

  it "rejects a malformed timestamp" do
    headers = headers_for(payload: payload, id: id, timestamp: "not-a-time", secret: secret)

    expect { described_class.verify_signature(payload: payload, headers: headers, secret: secret) }
      .to raise_error(Mailkube::SignatureVerificationError, /malformed/)
  end

  it "rejects a request missing the signature headers" do
    expect { described_class.verify_signature(payload: payload, headers: {}, secret: secret) }
      .to raise_error(Mailkube::SignatureVerificationError, /missing required/)
  end

  it "rejects a signature of the wrong length without raising from the comparison" do
    headers = headers_for(payload: payload, id: id, timestamp: Time.now.utc.iso8601, secret: secret)
    headers["X-Webhook-Sig"] = "sha256=deadbeef"

    expect { described_class.verify_signature(payload: payload, headers: headers, secret: secret) }
      .to raise_error(Mailkube::SignatureVerificationError, /signature mismatch/)
  end

  # A header mapping is not always a Hash. `ActionDispatch::Http::Headers` is Enumerable-only and
  # yields raw CGI env names, so both halves of that — no `transform_keys`, and `HTTP_`-prefixed,
  # underscored names — have to work, or every Rails receiver raises on `request.headers`.
  describe "header mappings that are not a Hash" do
    it "verifies against an Enumerable-only mapping that yields CGI env names" do
      signed = headers_for(payload: payload, id: id, timestamp: Time.now.utc.iso8601, secret: secret)
      rack = SpecHelpers::RackStyleHeaders.from_http(signed)

      expect(rack).not_to respond_to(:transform_keys)
      expect(described_class.verify_signature(payload: payload, headers: rack, secret: secret)).to eq(payload)
    end
  end

  # The two below tie `.sign` to that oracle from both directions: the value it produces, and the
  # verifier's acceptance of it.

  it "produces the same signature an independent HMAC does" do
    timestamp = "2026-01-01T00:00:00Z"
    expected = headers_for(payload: payload, id: id, timestamp: timestamp, secret: secret)["X-Webhook-Sig"]

    expect(described_class.sign(id: id, timestamp: timestamp, payload: payload, secret: secret)).to eq(expected)
  end

  it "produces a signature the verifier accepts" do
    timestamp = Time.now.utc.iso8601
    headers = {
      "X-Webhook-Id" => id,
      "X-Webhook-Ts" => timestamp,
      "X-Webhook-Sig" => described_class.sign(id: id, timestamp: timestamp, payload: payload, secret: secret)
    }

    expect(described_class.verify_signature(payload: payload, headers: headers, secret: secret)).to eq(payload)
  end
end
