# frozen_string_literal: true

module SpecHelpers
  # An HTTP adapter that answers a different canned response per call, in order.
  #
  # {StubAdapter} replies with one response forever, which is all a single-request verb needs.
  # Pagination is the first behaviour in this gem where the *sequence* is the thing under test:
  # page two has to be a different body from page one, or "follows the server's next link" cannot
  # be distinguished from "asked for the same page twice".
  class SequenceAdapter
    # @return [Array<Hash>] the requests this adapter received, in order.
    attr_reader :calls

    # @param bodies [Array<Object>] one response body per call; a Hash is JSON-encoded.
    def initialize(*bodies)
      @bodies = bodies.map { |body| body.is_a?(String) ? body : JSON.generate(body) }
      @calls = []
    end

    # @return [Mailkube::HttpResponse] the response for this position in the sequence.
    # @raise [RuntimeError] when the code under test made more requests than the spec set up,
    #   which is a failure worth seeing rather than a silent replay of the last page.
    def call(method:, url:, headers:, body: nil)
      @calls << { method: method, url: url, headers: headers, body: body }
      raise "unexpected request ##{@calls.size} to #{url}" if @calls.size > @bodies.size

      Mailkube::HttpResponse.new(status: 200, headers: {}, body: @bodies[@calls.size - 1])
    end
  end
end
