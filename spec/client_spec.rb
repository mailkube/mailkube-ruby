# frozen_string_literal: true

RSpec.describe Mailkube::Client do
  describe "configuration" do
    it "falls back to the environment for the API key" do
      allow(ENV).to receive(:fetch).with("MAILKUBE_API_KEY", nil).and_return("mk_env")
      allow(ENV).to receive(:fetch).with("MAILKUBE_BASE_URL", nil).and_return(nil)

      client = described_class.new(http: SpecHelpers::StubAdapter.new)

      expect(client.base_url).to eq(Mailkube::DEFAULT_BASE_URL)
    end

    it "raises when no API key is available anywhere" do
      allow(ENV).to receive(:fetch).with("MAILKUBE_API_KEY", nil).and_return(nil)

      expect { described_class.new(http: SpecHelpers::StubAdapter.new) }
        .to raise_error(Mailkube::ConfigurationError, /MAILKUBE_API_KEY/)
    end

    it "prefers an explicit base URL over the default" do
      client = described_class.new(api_key: "mk_test", base_url: "https://example.test/v1/",
                                   http: SpecHelpers::StubAdapter.new)

      expect(client.base_url).to eq("https://example.test/v1/")
    end

    it "is frozen, so it cannot be reconfigured after construction" do
      client, = client_with

      expect(client).to be_frozen
    end
  end

  describe "default headers" do
    it "sends bearer auth, JSON content negotiation and a versioned User-Agent" do
      client, adapter = client_with
      client.emails.send(**minimal_send)

      headers = adapter.calls.first[:headers]
      expect(headers).to include(
        "Authorization" => "Bearer mk_test",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      )
      expect(headers["User-Agent"]).to eq("mailkube-ruby/#{Mailkube::VERSION}")
    end

    it "appends a user-agent suffix after the SDK's own token" do
      # A wrapping tool gets attribution without hiding which SDK made the call.
      client, adapter = client_with_user_agent_suffix("my-cli/1.0.0")
      client.emails.send(**minimal_send)

      expect(adapter.calls.first[:headers]["User-Agent"])
        .to eq("mailkube-ruby/#{Mailkube::VERSION} my-cli/1.0.0")
    end

    it "ignores a suffix that is blank or could split the header" do
      # Dropped rather than cleaned: repairing it would hide the caller's bug.
      ["", "   ", "cli/1.0\ninjected: yes", "cli/1.0\rinjected: yes"].each do |suffix|
        client, adapter = client_with_user_agent_suffix(suffix)
        client.emails.send(**minimal_send)

        expect(adapter.calls.first[:headers]["User-Agent"]).to eq("mailkube-ruby/#{Mailkube::VERSION}")
      end
    end

    it "trims surrounding space from a user-agent suffix" do
      client, adapter = client_with_user_agent_suffix("  my-cli/1.0.0  ")
      client.emails.send(**minimal_send)

      expect(adapter.calls.first[:headers]["User-Agent"]).to end_with(" my-cli/1.0.0")
    end

    # The example above cannot fail on a malformed version: it interpolates the same constant the
    # code does, so `mailkube-ruby/vX.Y.Z` would satisfy it. The contract's row is
    # `mailkube-<lang>/<version>`, and the release path is exactly where a `v` could creep in —
    # `tagFormat` is `v${version}`, so a release step that took the version from the git tag rather
    # than from `${nextRelease.version}` would ship one. Asserting on the shape, not the value, is
    # what makes that structurally impossible.
    it "reports a bare version, with no `v` prefix, whatever the release path writes" do
      client, adapter = client_with
      client.emails.send(**minimal_send)

      user_agent = adapter.calls.first[:headers]["User-Agent"]
      expect(user_agent).to start_with("mailkube-ruby/")
      expect(user_agent.delete_prefix("mailkube-ruby/")).to match(/\A\d/)
    end

    it "reports the same version the gemspec publishes" do
      spec = Gem::Specification.load(File.expand_path("../mailkube.gemspec", __dir__))

      expect(spec.version.to_s).to eq(Mailkube::VERSION)
    end
  end

  describe "the origin guard" do
    it "resolves a relative path against the base URL" do
      client, adapter = client_with
      client.emails.send(**minimal_send)

      expect(adapter.calls.first[:url]).to eq("#{Mailkube::DEFAULT_BASE_URL}emails")
    end

    it "refuses an absolute URL on another origin" do
      config = Mailkube::Config.new(api_key: "mk_test")

      expect { config.build_url("https://evil.example/steal") }
        .to raise_error(Mailkube::ConfigurationError, /not on the configured API origin/)
    end

    it "allows an absolute URL the API itself issued" do
      config = Mailkube::Config.new(api_key: "mk_test")
      link = "#{Mailkube::DEFAULT_BASE_URL}emails?cursor=abc"

      expect(config.build_url(link)).to eq(link)
    end
  end
end
