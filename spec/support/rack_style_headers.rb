# frozen_string_literal: true

module SpecHelpers
  # A stand-in for `ActionDispatch::Http::Headers`.
  #
  # A header mapping is not always a Hash, and Rails' is the case that matters: it is Enumerable
  # only — no `transform_keys` — and its `#each` yields raw CGI env names (`HTTP_X_WEBHOOK_SIG`).
  # Both halves have to work or every Rails receiver raises on `request.headers`, so this double
  # reproduces both rather than just the missing-Hash-methods half.
  class RackStyleHeaders
    include Enumerable

    # @param env [Hash{String => String}] headers keyed by CGI env name.
    def initialize(env) = @env = env

    # @yield [String, String] each env name and its value.
    def each(&) = @env.each(&)

    # @param headers [Hash{String => String}] headers keyed by dashed HTTP name.
    # @return [RackStyleHeaders] the same headers in Rack's env spelling.
    def self.from_http(headers)
      new(headers.transform_keys { |name| "HTTP_#{name.upcase.tr("-", "_")}" })
    end
  end
end
