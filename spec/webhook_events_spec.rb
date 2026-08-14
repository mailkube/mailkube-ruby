# frozen_string_literal: true

require "json"

# Fixture payloads, at file scope so the guards below can compare against them without defining
# constants inside an example group. The values are deliberately minimal and unrealistic: these
# specs assert *shape*, not formatting.
module WebhookFixtures
  DELIVERY = { "recipient" => "b@y.com", "timestamp" => "t" }.freeze
  FAILURE = DELIVERY.merge("code" => 550, "reason" => "blocked").freeze
  OPEN = { "ipAddress" => "1.2.3.4", "userAgent" => "UA", "timestamp" => "t" }.freeze
  MESSAGE = {
    "email_id" => "e1", "created_at" => "2026-01-01T00:00:00Z", "domain" => "acme.com",
    "subject" => "Hi", "to" => ["b@y.com"], "from" => "a@x.com",
    "tags" => [{ "name" => "campaign", "value" => "welcome" }]
  }.freeze

  # One payload per registered event type. Every guard below reads from this hash, so an event
  # added to the registry without a fixture is a red test rather than an untested arm.
  PAYLOADS = {
    "email.sent" => MESSAGE.merge("sent" => DELIVERY),
    "email.delivered" => MESSAGE.merge("delivery" => DELIVERY),
    "email.bounced" => MESSAGE.merge("bounce" => FAILURE),
    "email.delivery_delayed" => MESSAGE.merge("delay" => FAILURE),
    "email.suppressed" => MESSAGE.merge("suppression" => { "recipients" => ["b@y.com"], "timestamp" => "t" }),
    "email.scheduled" => MESSAGE.merge("scheduled" => { "scheduled_at" => "t", "batch_id" => "b1" }),
    "email.failed" => MESSAGE.merge("failed" => { "reason" => "mta_unreachable", "timestamp" => "t" }),
    "email.opened" => MESSAGE.merge("open" => OPEN),
    "email.clicked" => MESSAGE.merge("click" => OPEN.merge("link" => "https://x/y")),
    "domain.status" => { "domain" => "acme.com", "status" => "active", "onboarding_state" => "production",
                         "previous" => { "status" => "on_hold", "onboarding_state" => "setup_in_progress" } },
    "webhook.status" => { "endpoint_url" => "https://x/hook", "is_active" => true, "is_deleted" => false,
                          "disabled_reason" => "none",
                          "previous" => { "is_active" => false, "is_deleted" => false,
                                          "disabled_reason" => "user" } }
  }.freeze

  # @return [String] a raw webhook body for one event type.
  def self.body(type, data) = JSON.generate("type" => type, "created_at" => "2026-01-01T00:00:00Z", "data" => data)
end

# The inbound event catalogue. Signature verification is in `webhooks_spec.rb`; this file is about
# what a verified body parses into.
RSpec.describe "the webhook event catalogue" do
  # @return [Mailkube::Events::Event] the parsed event for a fixture type.
  def parse(type, data = WebhookFixtures::PAYLOADS.fetch(type))
    Mailkube::Webhooks.parse_event(WebhookFixtures.body(type, data))
  end

  # Three guards that each catch a mistake the other two cannot. The registry is the catalogue, so
  # leg 1 pins it against the documented list, leg 2 pins the fixtures against it, and leg 3 proves
  # each row points at the right class — a wrong class still parses, via the unknown arm.
  describe "the registry is the catalogue" do
    it "registers exactly the documented event types" do
      expect(Mailkube::Events::REGISTRY.keys).to contain_exactly(
        "email.sent", "email.delivered", "email.bounced", "email.delivery_delayed",
        "email.suppressed", "email.scheduled", "email.failed", "email.opened",
        "email.clicked", "domain.status", "webhook.status"
      )
    end

    it "has a fixture payload for every registered type" do
      expect(WebhookFixtures::PAYLOADS.keys).to match_array(Mailkube::Events::REGISTRY.keys)
    end

    WebhookFixtures::PAYLOADS.each_key do |type|
      it "parses #{type} into its own envelope rather than the unknown arm" do
        event = parse(type)

        expect(event).to be_an_instance_of(Mailkube::Events::REGISTRY.fetch(type))
        expect(event.type).to eq(type)
        expect(event.created_at).to eq("2026-01-01T00:00:00Z")
      end
    end
  end

  describe "the message block every email event shares" do
    it "reads the fields the send supplied, including the wire's bare from" do
      data = parse("email.delivered").data

      expect(data).to have_attributes(email_id: "e1", domain: "acme.com", subject: "Hi", from: "a@x.com")
      expect(data.to).to eq(["b@y.com"])
    end

    it "keeps tags as plain hashes, so an unknown key inside a tag survives" do
      tagged = WebhookFixtures::PAYLOADS.fetch("email.delivered")
                                        .merge("tags" => [{ "name" => "c", "value" => "w", "future_tag" => 3 }])

      expect(parse("email.delivered", tagged).data.tags.first).to include("future_tag" => 3)
    end

    it "defaults tags to empty when the server sent none" do
      bare = WebhookFixtures::PAYLOADS.fetch("email.delivered").reject { |key, _| key == "tags" }

      expect(parse("email.delivered", bare).data.tags).to eq([])
    end
  end

  describe "the nested blocks" do
    it "reads a delivery outcome" do
      expect(parse("email.delivered").data.delivery).to have_attributes(recipient: "b@y.com", timestamp: "t")
    end

    it "reads a bounce as a delivery outcome plus a verdict, mirroring the server's inheritance" do
      expect(parse("email.bounced").data.bounce).to have_attributes(recipient: "b@y.com", code: 550,
                                                                    reason: "blocked")
    end

    it "reuses the delivery block for a sent event" do
      expect(parse("email.sent").data.sent.recipient).to eq("b@y.com")
    end

    it "maps the camelCase engagement keys, which are the only camelCase keys on the wire" do
      expect(parse("email.opened").data.open).to have_attributes(ip_address: "1.2.3.4", user_agent: "UA")
    end

    it "reads a click as an open plus the link" do
      expect(parse("email.clicked").data.click).to have_attributes(ip_address: "1.2.3.4", link: "https://x/y")
    end

    it "reads the snake_case scheduling keys" do
      expect(parse("email.scheduled").data.scheduled).to have_attributes(scheduled_at: "t", batch_id: "b1")
    end

    it "keeps a send-failure reason a plain string, so an unpublished reason still parses" do
      unpublished = WebhookFixtures::PAYLOADS.fetch("email.failed")
                                             .merge("failed" => { "reason" => "something_new", "timestamp" => "t" })

      expect(parse("email.failed", unpublished).data.failed.reason).to eq("something_new")
    end

    it "reads a domain status change and the state it came from" do
      data = parse("domain.status").data

      expect(data).to have_attributes(domain: "acme.com", status: "active")
      expect(data.previous).to have_attributes(status: "on_hold", onboarding_state: "setup_in_progress")
    end

    it "spells the webhook booleans as predicates, over the wire's is_ keys" do
      data = parse("webhook.status").data

      expect(data).to have_attributes(endpoint_url: "https://x/hook", active?: true, deleted?: false)
      expect(data.previous.active?).to be(false)
    end

    it "tolerates a nested block the server omitted entirely" do
      expect(parse("email.delivered", WebhookFixtures::MESSAGE).data.delivery.recipient).to be_nil
    end
  end

  describe "the two inversions of the response-model rules" do
    it "degrades an unrecognized type instead of raising, so a new event never breaks a receiver" do
      event = Mailkube::Webhooks.parse_event(WebhookFixtures.body("email.reopened", { "anything" => 1 }))

      expect(event).to be_an_instance_of(Mailkube::Events::UnknownEvent)
      expect(event.type).to eq("email.reopened")
      expect(event.data).to eq("anything" => 1)
    end

    it "keeps a field this release has never heard of, at every nesting depth" do
      nested = WebhookFixtures::DELIVERY.merge("future_nested" => 2)
      payload = WebhookFixtures::PAYLOADS.fetch("email.delivered")
                                         .merge("future_top" => 1, "delivery" => nested)
      event = parse("email.delivered", payload)

      expect(event.data["future_top"]).to eq(1)
      expect(event.data.delivery["future_nested"]).to eq(2)
    end

    it "round-trips the raw payload verbatim, so a receiver can forward what it was sent" do
      raw = WebhookFixtures.body("email.delivered", WebhookFixtures::PAYLOADS.fetch("email.delivered"))

      expect(Mailkube::Webhooks.parse_event(raw).to_h).to eq(JSON.parse(raw))
    end
  end

  describe "parsing" do
    it "freezes the decoded payload all the way down, so a forwarded event cannot be altered" do
      event = parse("email.delivered")

      expect { event.data.raw["recipient"] = "x" }.to raise_error(FrozenError)
    end

    it "reports a body that is not JSON at all" do
      expect { Mailkube::Webhooks.parse_event("not json") }
        .to raise_error(Mailkube::Error, /not valid JSON/)
    end

    it "reports a JSON body that is not an object" do
      expect { Mailkube::Webhooks.parse_event("[1, 2, 3]") }
        .to raise_error(Mailkube::Error, /not a JSON object/)
    end

    it "is frozen and value-comparable, like every other model here" do
      event = parse("email.delivered")
      same_payload_again = parse("email.delivered")

      expect(event).to eq(same_payload_again)
      expect(event).to be_frozen
    end
  end

  describe "the verify combinator" do
    it "verifies the signature and hands back a typed event in one call" do
      raw = WebhookFixtures.body("email.delivered", WebhookFixtures::PAYLOADS.fetch("email.delivered"))
      timestamp = Time.now.utc.iso8601
      digest = OpenSSL::HMAC.hexdigest("SHA256", "whsec", "evt_1.#{timestamp}.#{raw}")
      headers = { "X-Webhook-Id" => "evt_1", "X-Webhook-Ts" => timestamp, "X-Webhook-Sig" => "sha256=#{digest}" }

      expect(Mailkube::Webhooks.verify(payload: raw, headers: headers, secret: "whsec"))
        .to be_an_instance_of(Mailkube::Events::EmailDeliveredEvent)
    end

    it "refuses to parse anything when the signature does not verify" do
      raw = WebhookFixtures.body("email.delivered", WebhookFixtures::PAYLOADS.fetch("email.delivered"))
      headers = { "X-Webhook-Id" => "evt_1", "X-Webhook-Ts" => Time.now.utc.iso8601,
                  "X-Webhook-Sig" => "sha256=deadbeef" }

      expect { Mailkube::Webhooks.verify(payload: raw, headers: headers, secret: "whsec") }
        .to raise_error(Mailkube::SignatureVerificationError)
    end
  end
end
