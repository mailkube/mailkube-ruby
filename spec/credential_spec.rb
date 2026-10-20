# frozen_string_literal: true

# The `credential` namespace: the calling API key describing itself.
RSpec.describe Mailkube::Resources::Credential do
  let(:base) { Mailkube::DEFAULT_BASE_URL }
  let(:monthly) do
    { "name" => "emails_per_month", "limit" => 50_000, "used" => 9310, "remaining" => 40_690, "period" => "2026-10" }
  end
  let(:plan) do
    { "code" => "00000000-0000-0000-0000-000000000003", "name" => "Momentum", "status" => "active",
      "quotas" => [{ "name" => "emails_per_day", "limit" => 5000, "used" => 120, "remaining" => 4880,
                     "period" => "2026-10-19" }, monthly] }
  end
  let(:key) do
    { "object" => "api_key", "key_id" => "k3v9x2m8q1w7r4t6y0p5s2a8", "name" => "production-backend",
      "description" => nil, "created_at" => "2026-09-02T08:14:03Z", "last_auth_at" => "2026-10-19T16:41:22Z",
      "allowed_source_ips" => ["203.0.113.0/24"], "domain" => { "name" => "example.com" },
      "organization" => { "name" => "Example Ltd", "alias" => "example" }, "plan" => plan }
  end

  it "gets the calling key's own description, with no body and no idempotency key" do
    client, adapter = client_with(body: key)
    client.credential.info

    expect(adapter.calls.first).to include(method: "GET", url: "#{base}api-keys/me", body: nil)
    expect(adapter.calls.first[:headers].keys.map(&:downcase)).not_to include("idempotency-key")
  end

  it "decodes the key, its domain, organization and plan" do
    client, = client_with(body: key)
    info = client.credential.info

    expect(info).to have_attributes(
      object: "api_key", key_id: "k3v9x2m8q1w7r4t6y0p5s2a8", name: "production-backend", description: nil,
      created_at: "2026-09-02T08:14:03Z", last_auth_at: "2026-10-19T16:41:22Z",
      allowed_source_ips: ["203.0.113.0/24"]
    )
    expect(info.domain.name).to eq("example.com")
    expect([info.organization.name, info.organization.alias]).to eq(["Example Ltd", "example"])
    expect([info.plan.code, info.plan.name, info.plan.status])
      .to eq(%w[00000000-0000-0000-0000-000000000003 Momentum active])
    expect(info.plan.quotas.first).to have_attributes(name: "emails_per_day", limit: 5000, used: 120,
                                                      remaining: 4880, period: "2026-10-19")
  end

  it "reads a null plan as no plan, never as an empty one" do
    client, = client_with(body: key.merge("plan" => nil))

    expect(client.credential.info.plan).to be_nil
  end

  it "reads an absent plan as no plan" do
    client, = client_with(body: key.except("plan"))

    expect(client.credential.info.plan).to be_nil
  end

  it "keeps a monthly-only plan monthly-only, synthesizing no daily quota" do
    client, = client_with(body: key.merge("plan" => plan.merge("quotas" => [monthly])))

    expect(client.credential.info.plan.quotas.map(&:name)).to eq(["emails_per_month"])
  end

  it "raises an authentication error for a refused key" do
    client, = client_with(status: 403, body: { "name" => "invalid_api_key", "message" => "API key is invalid" })

    expect { client.credential.info }.to raise_error(Mailkube::AuthenticationError) do |error|
      expect(error.error_name).to eq(Mailkube::ErrorName::INVALID_API_KEY)
    end
  end

  it "carries Retry-After on a rate limit" do
    client, = client_with(status: 429, body: { "name" => "rate_limit_exceeded", "message" => "slow down" },
                          headers: { "retry-after" => "59" })

    expect { client.credential.info }.to raise_error(Mailkube::RateLimitError) do |error|
      expect(error.retry_after).to eq(59)
    end
  end

  it "refuses a 2xx body that is not a JSON object" do
    client, = client_with(body: "[]")

    expect { client.credential.info }.to raise_error(Mailkube::Error, /expected a JSON object/) do |error|
      expect(error).not_to be_a(Mailkube::APIError)
    end
  end
end
