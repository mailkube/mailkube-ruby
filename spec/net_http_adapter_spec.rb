# frozen_string_literal: true

# The default adapter's happy path is covered end to end by `concurrency_spec.rb`, which drives it
# over a real socket. What is left here is the handful of paths that never happen against a
# working server, and which would otherwise be untested code shipped to every consumer.
RSpec.describe Mailkube::NetHttpAdapter do
  subject(:adapter) { described_class.new(timeout: 1) }

  it "translates a transport failure into a ConnectionError" do
    # Port 1 on the loopback interface refuses connections; nothing is listening there.
    expect { adapter.call(method: "POST", url: "http://127.0.0.1:1/emails", headers: {}) }
      .to raise_error(Mailkube::ConnectionError, /Errno::/)
  end

  it "refuses an HTTP method it cannot issue rather than reaching for const_get" do
    expect { adapter.call(method: "TRACE", url: "http://127.0.0.1:1/emails", headers: {}) }
      .to raise_error(Mailkube::ConfigurationError, /unsupported HTTP method/)
  end

  it "refuses a URL with no host" do
    expect { adapter.call(method: "POST", url: "/emails", headers: {}) }
      .to raise_error(Mailkube::ConfigurationError, /no host/)
  end

  # `rescue Mailkube::Error` is the documented way to catch everything this gem raises, so a
  # `URI::InvalidURIError` escaping from here would make that promise false. Every other thing this
  # adapter refuses already raises ConfigurationError; this was the one that did not.
  it "wraps a malformed URL in its own error rather than leaking URI's" do
    expect { adapter.call(method: "POST", url: "http://[", headers: {}) }
      .to raise_error(Mailkube::ConfigurationError, /invalid URL/)
  end

  # The timeout is a public constructor argument, and an argument that is stored but never read is
  # indistinguishable from one that works until you need it. Asserting it reaches `Net::HTTP.start`
  # is what stops it going quietly dead in a refactor.
  it "applies the configured timeout to the connection it opens" do
    opened = nil
    allow(Net::HTTP).to receive(:start) { |*_args, **options| opened = options }

    described_class.new(timeout: 7).call(method: "GET", url: "https://example.test/x", headers: {})

    expect(opened).to include(open_timeout: 7, read_timeout: 7)
  end

  it "is frozen, like every other collaborator the client wires up" do
    expect(adapter).to be_frozen
  end
end
