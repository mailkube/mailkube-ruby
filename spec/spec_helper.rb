# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  # `skip`, not the older `add_filter`, which SimpleCov 1.x deprecates.
  skip "/spec/"
  skip "/examples/"
  # Branch coverage is opt-in: without this line `minimum_coverage branch:` silently gates
  # nothing, which is how a repo ends up believing it has a branch gate that it does not.
  enable_coverage :branch
  minimum_coverage line: 90, branch: 90
end

require "json"
require "mailkube"

# Helpers shared by the whole suite.
#
# The injection seam is the test seam: {StubAdapter} is passed through `Client.new(http:)`, so
# every spec exercises the real config resolution, request building, error mapping and response
# parsing while making zero network calls. The one exception is `concurrency_spec.rb`, which
# needs real sockets and brings its own server.
module SpecHelpers
  # An HTTP adapter that records what it was asked to send and replies with a canned response.
  class StubAdapter
    # @return [Array<Hash>] the requests this adapter received, in order.
    attr_reader :calls

    # @param status [Integer] the status to reply with.
    # @param body [Object] the response body; a Hash is JSON-encoded, a String is sent verbatim.
    # @param headers [Hash{String => String}] response headers, keys downcased.
    def initialize(status: 200, body: { "id" => "abc123" }, headers: {})
      @status = status
      @body = body.is_a?(String) ? body : JSON.generate(body)
      @headers = headers
      @calls = []
    end

    # @return [Mailkube::HttpResponse] the canned response.
    def call(method:, url:, headers:, body: nil)
      @calls << { method: method, url: url, headers: headers, body: body.nil? ? nil : JSON.parse(body) }
      Mailkube::HttpResponse.new(status: @status, headers: @headers, body: @body)
    end
  end

  # An adapter that raises instead of answering, for the transport-failure paths.
  class RaisingAdapter
    # @param error [Exception] the error to raise on every call.
    def initialize(error) = @error = error

    # @raise [Exception] always.
    def call(**) = raise @error
  end

  # @return [Array(Mailkube::Client, StubAdapter)] a client wired to a fresh stub adapter.
  def client_with(**options)
    adapter = StubAdapter.new(**options)
    [Mailkube::Client.new(api_key: "mk_test", http: adapter), adapter]
  end

  # A client that identifies a wrapping tool, plus the adapter recording what it sent.
  #
  # @param suffix [String, nil] the `name/version` token to append to the User-Agent.
  # @return [Array(Mailkube::Client, StubAdapter)] the client and its adapter.
  def client_with_user_agent_suffix(suffix)
    adapter = StubAdapter.new
    client = Mailkube::Client.new(api_key: "mk_test", http: adapter, user_agent_suffix: suffix)
    [client, adapter]
  end

  # @return [Hash] the smallest valid set of send parameters.
  def minimal_send = { from: "a@x.com", to: "b@y.com", subject: "Hi" }
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
end
