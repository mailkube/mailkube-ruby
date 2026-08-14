# frozen_string_literal: true

require_relative "support/barrier_server"

# One client instance is safe to share across concurrent callers, and this proves it.
#
# `SDK_CONTRACT.md` requires more than "no exception was raised": it requires that concurrent
# calls **do not observe each other's responses**. A client sharing one connection does not crash
# when two threads overlap, it hands one thread the other's body. Inside a single process that is
# a confidentiality bug, and it passes any assertion weaker than this one.
#
# Ruby releases the GVL around socket I/O, so plain threads give real HTTP concurrency with no
# setup at all. Fibers would too, but only with a scheduler installed, which Ruby does not ship;
# see `.rules/SDK_DESIGN.md`.
#
# Why the server holds every request at a barrier is documented on {SpecHelpers::BarrierServer}.
RSpec.describe "concurrent use of one client" do
  let(:calls) { 32 }
  let(:server) { SpecHelpers::BarrierServer.new(calls) }
  let(:client) { Mailkube::Client.new(api_key: "mk_test", base_url: server.base_url) }

  after { server.shutdown }

  it "does not let concurrent calls observe each other's responses" do
    keys = Array.new(calls) { |index| format("idem-%03d", index) }
    # Force the memoized client (and the server behind it) before any thread touches it: `let`
    # memoization is not itself thread-safe, and racing on it would be a bug in the spec.
    sdk = client

    received = keys.map { |key| Thread.new { send_with(sdk, key) } }.map(&:value)

    received.zip(keys).each do |got, key|
      expect(got).to eq(key), "#{key} received the response for #{got.inspect}: concurrent calls observed each other"
    end
  end

  def send_with(sdk, key)
    sdk.emails.send(from: "a@x.com", to: "b@y.com", subject: "Hi", idempotency_key: key).id
  end
end
