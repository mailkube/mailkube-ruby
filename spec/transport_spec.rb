# frozen_string_literal: true

# The transport is exercised indirectly by every other spec. What is left here is the behaviour a
# one-verb scaffold cannot reach through `emails.send`, and which the next verb added to this SDK
# will rely on.
RSpec.describe Mailkube::Transport do
  let(:adapter) { SpecHelpers::StubAdapter.new }
  let(:transport) { described_class.new(Mailkube::Config.new(api_key: "mk_test"), adapter) }

  it "sends no body at all for a body-less request, rather than an empty JSON object" do
    transport.send_email(Mailkube::RequestSpec.new(path: "emails", method: "GET"))

    expect(adapter.calls.first).to include(method: "GET", body: nil)
  end

  it "merges per-request headers over the client defaults without losing them" do
    transport.send_email(Mailkube::RequestSpec.new(path: "emails", headers: { "X-Trace" => "1" }))

    expect(adapter.calls.first[:headers]).to include("Authorization" => "Bearer mk_test", "X-Trace" => "1")
  end

  it "treats a JSON body that is not an object as no body at all" do
    array_adapter = SpecHelpers::StubAdapter.new(body: "[1, 2, 3]")
    array_transport = described_class.new(Mailkube::Config.new(api_key: "mk_test"), array_adapter)

    expect { array_transport.send_email(Mailkube::RequestSpec.new(path: "emails")) }
      .to raise_error(Mailkube::APIError, /expected a JSON body with an 'id'/)
  end

  it "is frozen, like every other collaborator the client wires up" do
    expect(transport).to be_frozen
  end

  describe "the query string" do
    it "sends no query string at all when nothing is filtered, rather than a bare question mark" do
      transport.send_email(Mailkube::RequestSpec.new(path: "emails", method: "GET"))

      expect(adapter.calls.first[:url]).to eq("#{Mailkube::DEFAULT_BASE_URL}emails")
    end

    it "renders the spec's params onto the URL" do
      transport.send_email(Mailkube::RequestSpec.new(path: "emails", method: "GET",
                                                     params: { "status" => "scheduled,canceled", "page" => "2" }))

      expect(adapter.calls.first[:url]).to eq("#{Mailkube::DEFAULT_BASE_URL}emails?status=scheduled%2Ccanceled&page=2")
    end

    it "leaves the query an absolute page link already carries untouched" do
      link = "#{Mailkube::DEFAULT_BASE_URL}scheduled-emails?page=2&status=scheduled"
      transport.send_email(Mailkube::RequestSpec.new(path: link, method: "GET"))

      expect(adapter.calls.first[:url]).to eq(link)
    end
  end

  describe "requesting a decoded object" do
    it "returns the decoded body, leaving the resource to name its model" do
      object_adapter = SpecHelpers::StubAdapter.new(body: { "object" => "scheduled_email.batch",
                                                            "canceled_count" => 4 })
      object_transport = described_class.new(Mailkube::Config.new(api_key: "mk_test"), object_adapter)

      expect(object_transport.request_json(Mailkube::RequestSpec.new(path: "x", method: "GET")))
        .to eq("object" => "scheduled_email.batch", "canceled_count" => 4)
    end

    it "rejects a 2xx body that is not a JSON object, rather than yielding an empty model" do
      array_transport = described_class.new(Mailkube::Config.new(api_key: "mk_test"),
                                            SpecHelpers::StubAdapter.new(body: "[1, 2, 3]"))

      expect { array_transport.request_json(Mailkube::RequestSpec.new(path: "x", method: "GET")) }
        .to raise_error(Mailkube::APIError, /expected a JSON object body/)
    end

    it "rejects an empty 2xx body for the same reason" do
      empty_transport = described_class.new(Mailkube::Config.new(api_key: "mk_test"),
                                            SpecHelpers::StubAdapter.new(body: ""))

      expect { empty_transport.request_json(Mailkube::RequestSpec.new(path: "x", method: "GET")) }
        .to raise_error(Mailkube::APIError, /expected a JSON object body/)
    end

    it "maps a non-2xx exactly as the send verb does, because both go through one place" do
      failing = described_class.new(Mailkube::Config.new(api_key: "mk_test"),
                                    SpecHelpers::StubAdapter.new(status: 404, body: { "name" => "not_found" }))

      expect { failing.request_json(Mailkube::RequestSpec.new(path: "x", method: "GET")) }
        .to raise_error(Mailkube::NotFoundError)
    end
  end
end
