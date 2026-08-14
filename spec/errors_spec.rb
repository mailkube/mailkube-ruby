# frozen_string_literal: true

RSpec.describe "the error taxonomy" do
  # One table, one expectation per row. A new status becomes a row here and a row in
  # STATUS_ERRORS, and nowhere else.
  {
    400 => Mailkube::BadRequestError,
    403 => Mailkube::AuthenticationError,
    404 => Mailkube::NotFoundError,
    409 => Mailkube::ConflictError,
    422 => Mailkube::InvalidRequestError,
    429 => Mailkube::RateLimitError,
    500 => Mailkube::ServerError,
    503 => Mailkube::ServerError,
    418 => Mailkube::APIError
  }.each do |status, klass|
    it "maps HTTP #{status} to #{klass}" do
      client, = client_with(status: status, body: { "name" => "boom", "message" => "it broke" })

      expect { client.emails.send(**minimal_send) }.to raise_error(klass, "it broke")
    end
  end

  # The documented error names, written out by hand.
  #
  # Deliberately a literal rather than anything derived from `ErrorName`, because a test that
  # reads the constant it is checking can only ever agree with it: a dropped or misspelled member
  # would change both sides together and pass. Spelled out here, a drift fails structurally, and it
  # fails without needing the public error reference or another SDK's checkout on disk.
  #
  # This mirrors `mailkube-python`'s `_exceptions.py`, which is the reference list at 30 members.
  # When the API adds a name, it lands in both places in the same change.
  let(:documented_error_names) do
    %w[
      application_error body_content_rejected browser_not_allowed concurrent_idempotent_requests
      from_domain_not_allowed invalid_api_key invalid_attachment invalid_from_address
      invalid_idempotency_key invalid_idempotent_request invalid_request_body
      link_reputation_blocked max_message_size_exceeded max_recipients_exceeded method_not_allowed
      missing_required_field missing_required_variable missing_user_agent not_acceptable
      quota_exceeded rate_limit_exceeded scheduled_email_not_found scheduled_email_not_pending
      scheduling_not_included template_not_found template_not_published topic_disabled
      topic_not_found unsupported_media_type validation_error
    ]
  end

  it "carries the whole envelope, not just the message" do
    client, = client_with(status: 429, body: { "name" => Mailkube::ErrorName::RATE_LIMIT_EXCEEDED,
                                               "message" => "slow down" },
                          headers: { "retry-after" => "12", "x-request-id" => "req_1" })

    expect { client.emails.send(**minimal_send) }.to raise_error(Mailkube::RateLimitError) { |error|
      expect(error).to have_attributes(
        error_name: "rate_limit_exceeded", status_code: 429, retry_after: 12, request_id: "req_1"
      )
      expect(error.body).to include("message" => "slow down")
    }
  end

  # The gateway only started sending `X-Request-Id` in August 2026, so until now nothing would have
  # noticed the lookup failing. `HttpResponse` is public — third-party adapters construct it — and
  # "keys are downcased" used to be the adapter's obligation rather than an enforced invariant, so
  # an adapter passing the header through in the server's own casing produced a silent nil. The
  # fixture casing here is deliberately not the casing the lookup uses.
  it "finds the request id whatever casing the adapter used for the header" do
    client, = client_with(status: 404, body: { "name" => "not_found", "message" => "gone" },
                          headers: { "X-Request-Id" => "req_mixed_case" })

    expect { client.emails.send(**minimal_send) }.to raise_error(Mailkube::NotFoundError) { |error|
      expect(error.request_id).to eq("req_mixed_case")
    }
  end

  it "still maps by status when the error body is not JSON at all" do
    client, = client_with(status: 500, body: "<html>502 Bad Gateway</html>")

    expect { client.emails.send(**minimal_send) }.to raise_error(Mailkube::ServerError, "HTTP 500")
  end

  it "reports an unrecognized error name verbatim rather than coercing it" do
    client, = client_with(status: 400, body: { "name" => "invented_next_year", "message" => "?" })

    expect { client.emails.send(**minimal_send) }
      .to raise_error(Mailkube::BadRequestError) { |error| expect(error.error_name).to eq("invented_next_year") }
  end

  it "wraps a transport failure as a ConnectionError, not an APIError" do
    adapter = SpecHelpers::RaisingAdapter.new(Mailkube::ConnectionError.new("timed out"))
    client = Mailkube::Client.new(api_key: "mk_test", http: adapter)

    expect { client.emails.send(**minimal_send) }.to raise_error(Mailkube::ConnectionError, "timed out")
  end

  it "falls back to the error name when the envelope carries no message" do
    client, = client_with(status: 403, body: { "name" => Mailkube::ErrorName::INVALID_API_KEY })

    expect { client.emails.send(**minimal_send) }
      .to raise_error(Mailkube::AuthenticationError, "invalid_api_key")
  end

  it "puts every error under one rescuable base class" do
    expect(Mailkube::RateLimitError.ancestors).to include(Mailkube::APIError, Mailkube::Error, StandardError)
  end

  it "exposes every documented error name as a constant, and no invented ones" do
    declared = Mailkube::ErrorName.constants.map { |name| Mailkube::ErrorName.const_get(name) }

    expect(declared).to match_array(documented_error_names)
  end

  it "names each constant after its own value, so a typo cannot hide behind a plausible constant" do
    mismatched = Mailkube::ErrorName.constants.reject do |name|
      Mailkube::ErrorName.const_get(name) == name.to_s.downcase
    end

    expect(mismatched).to be_empty
  end
end
