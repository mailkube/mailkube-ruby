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
end
