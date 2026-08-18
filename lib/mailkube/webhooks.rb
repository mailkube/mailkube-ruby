# frozen_string_literal: true

require "openssl"
require "time"
require "json"

module Mailkube
  # Webhook signature verification and event parsing.
  #
  # Verification is pure and dependency-free: no client instance, no configuration, so you call
  # it directly inside your webhook handler.
  module Webhooks
    # How stale a webhook timestamp may be, in seconds, before it is rejected.
    DEFAULT_TOLERANCE = 300
    # The prefix the server puts before the hex digest in `X-Webhook-Sig`.
    SIGNATURE_PREFIX = "sha256="
    # Decode webhook payloads deep-frozen, so a receiver cannot mutate an event it is about to
    # forward or log. Passed **positionally** because that is the shape `JSON.parse` declares
    # (`(source, opts)`); as keywords Steep reports an unexpected keyword.
    PARSE_OPTIONS = { freeze: true }.freeze

    # Verify a webhook's signature and timestamp freshness over the raw body.
    #
    # The signed input is `"{id}.{timestamp}."` followed by the **raw** body, HMAC-SHA256 keyed
    # by the endpoint's signing secret, hex-encoded, and sent as `X-Webhook-Sig: sha256=<hex>`.
    # `X-Webhook-Ts` is an ISO-8601 timestamp checked for freshness; `X-Webhook-Id` is stable
    # across retries, so use it to deduplicate.
    #
    # Verify against the bytes you received. Never parse the body and re-encode it first: JSON
    # round-tripping reorders keys and normalizes whitespace, and the signature will not match.
    # In Rails that means `request.raw_post`, not `params`.
    #
    # @param payload [String] the raw request body.
    # @param headers [Hash{String => String}] the request headers, in any casing.
    # @param secret [String] the endpoint's signing secret.
    # @param tolerance [Integer] the freshness window in seconds.
    # @return [String] the verified payload, so a caller can parse it in one expression.
    # @raise [SignatureVerificationError] when a header is missing, the timestamp is stale, or
    #   the signature does not match.
    def self.verify_signature(payload:, headers:, secret:, tolerance: DEFAULT_TOLERANCE)
      lookup = normalize_headers(headers)
      id = lookup["x-webhook-id"]
      timestamp = lookup["x-webhook-ts"]
      signature = lookup["x-webhook-sig"]
      if id.nil? || timestamp.nil? || signature.nil?
        raise SignatureVerificationError, "missing required webhook signature headers"
      end

      check_freshness(timestamp, tolerance)
      check_signature(payload, id, timestamp, signature, secret)
      payload
    end

    # Parse a raw webhook body into a typed event.
    #
    # An event type this release has never heard of comes back as {Events::UnknownEvent} rather
    # than raising: a receiver keeps working when the platform adds a type, with no SDK upgrade.
    # That is the contract's deliberate inversion of the response-model rules, and it is why the
    # dispatch is a `fetch` with a default rather than a conditional — an unknown type is the last
    # row of the table, not an error path.
    #
    # Unknown *fields* survive too, at every depth: see {Events::Node}.
    #
    # @param payload [String] the raw request body.
    # @return [Events::Event] the parsed event; narrow it with `case` or `is_a?`.
    # @raise [Error] when the body is not a JSON object.
    def self.parse_event(payload)
      body = JSON.parse(payload, PARSE_OPTIONS)
      raise Error, "webhook payload is not a JSON object" unless body.is_a?(Hash)

      Events::REGISTRY.fetch(body["type"], Events::UnknownEvent).new(body)
    rescue JSON::ParserError => e
      raise Error, "webhook payload is not valid JSON: #{e.message}"
    end

    # Verify a webhook's signature and return the parsed event.
    #
    # The combinator most handlers actually want. It composes cleanly only because
    # {verify_signature} returns the verified payload rather than true.
    #
    # @param payload [String] the raw request body.
    # @param headers [Hash{String => String}, Enumerable] the request headers, in any casing.
    # @param secret [String] the endpoint's signing secret.
    # @param tolerance [Integer] the freshness window in seconds.
    # @return [Events::Event] the verified, parsed event.
    # @raise [SignatureVerificationError] when verification fails.
    # @raise [Error] when the verified body is not valid JSON.
    def self.verify(payload:, headers:, secret:, tolerance: DEFAULT_TOLERANCE)
      parse_event(verify_signature(payload: payload, headers: headers, secret: secret, tolerance: tolerance))
    end

    # Produce the `X-Webhook-Sig` value for a payload, the mirror of {verify_signature}.
    #
    # This exists so anything that produces a delivery — a fixture, a local replay tool, a fake
    # endpoint in your own suite — computes the signature the way this module verifies it. A
    # reimplementation from the docs above agrees with its author's reading of the prose rather
    # than with this SDK, and the two drift silently. Production code verifies; it does not sign.
    #
    # Freshness is not this method's concern: it signs the timestamp it is given, so replaying an
    # old capture reproduces the original signature exactly.
    #
    # @param id [String] the `X-Webhook-Id` value.
    # @param timestamp [String] the `X-Webhook-Ts` value, ISO-8601.
    # @param payload [String] the raw body that will be sent.
    # @param secret [String] the endpoint's signing secret.
    # @return [String] the header value, including the `sha256=` prefix.
    def self.sign(id:, timestamp:, payload:, secret:)
      SIGNATURE_PREFIX + signature_hex(id, timestamp, payload, secret)
    end

    # Return the hex HMAC-SHA256 over the contract's signed input.
    #
    # One implementation, so signing and verifying cannot disagree.
    #
    # @param id [String] the `X-Webhook-Id` value.
    # @param timestamp [String] the `X-Webhook-Ts` value.
    # @param payload [String] the raw body.
    # @param secret [String] the signing secret.
    # @return [String] the hex digest, without the prefix.
    def self.signature_hex(id, timestamp, payload, secret)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{id}.#{timestamp}.#{payload}")
    end
    private_class_method :signature_hex

    # Normalize a header mapping to lowercase, dashed names.
    #
    # This accepts more than a Hash on purpose. `ActionDispatch::Http::Headers` is `Enumerable`
    # but **not** a Hash, so the obvious `headers.transform_keys` raises `NoMethodError` on
    # `request.headers` — which is exactly what a Rails receiver passes. Nor is `to_h` a fix:
    # Rails' `#each` yields raw CGI env names, so a `to_h`-based lookup sees `HTTP_X_WEBHOOK_SIG`
    # and never matches `x-webhook-sig`.
    #
    # Stripping the `http_` prefix and swapping underscores for dashes maps both spellings onto
    # one, so a plain Hash, a Rack env and `request.headers` all work.
    #
    # @param headers [Hash{String => String}, Enumerable] the request headers, in any casing.
    # @return [Hash{String => String}] the headers keyed by lowercase dashed name.
    def self.normalize_headers(headers)
      # Iterated with a block rather than collected through `each.to_h`, because a mapping is only
      # required to yield — it is not required to hand back an Enumerator when called bare.
      normalized = {} #: Hash[String, String]
      headers.each { |name, value| normalized[canonical_header(name)] = value.to_s }
      normalized
    end
    private_class_method :normalize_headers

    # @param name [Object] a header name in any casing, dashed or in CGI env form.
    # @return [String] the lowercase, dashed form.
    def self.canonical_header(name) = name.to_s.downcase.delete_prefix("http_").tr("_", "-")
    private_class_method :canonical_header

    # @param timestamp [String] the ISO-8601 `X-Webhook-Ts` value.
    # @param tolerance [Integer] the freshness window in seconds.
    # @raise [SignatureVerificationError] when malformed or outside the window.
    def self.check_freshness(timestamp, tolerance)
      begin
        parsed = Time.iso8601(timestamp)
      rescue ArgumentError
        raise SignatureVerificationError, "malformed X-Webhook-Ts timestamp"
      end

      return if (Time.now - parsed).abs <= tolerance

      raise SignatureVerificationError, "timestamp is outside the freshness window"
    end
    private_class_method :check_freshness

    # @param payload [String] the raw body.
    # @param id [String] the `X-Webhook-Id` value.
    # @param timestamp [String] the `X-Webhook-Ts` value.
    # @param signature [String] the `X-Webhook-Sig` value.
    # @param secret [String] the signing secret.
    # @raise [SignatureVerificationError] when the digests differ.
    def self.check_signature(payload, id, timestamp, signature, secret)
      expected = signature_hex(id, timestamp, payload, secret)
      provided = signature.delete_prefix(SIGNATURE_PREFIX)
      # Length is compared first because `fixed_length_secure_compare` raises on a mismatch, and
      # the length of a hex digest is not a secret.
      return if provided.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(provided, expected)

      raise SignatureVerificationError, "signature mismatch"
    end
    private_class_method :check_signature
  end
end
