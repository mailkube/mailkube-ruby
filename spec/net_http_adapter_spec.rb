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

  it "is frozen, like every other collaborator the client wires up" do
    expect(adapter).to be_frozen
  end
end
