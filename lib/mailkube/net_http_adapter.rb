# frozen_string_literal: true

require "net/http"
require "openssl"
require "socket"
require "timeout"
require "uri"

module Mailkube
  # The default HTTP adapter, and the only file in this gem that touches `Net::HTTP`.
  #
  # ## The adapter contract
  #
  # An adapter responds to `#call(method:, url:, headers:, body:)` and returns an
  # {HttpResponse}. It raises {ConnectionError} when the request never produced a response, and
  # raises nothing else: mapping an HTTP status to an exception is {Transport}'s job, so a
  # replacement adapter never has to know the API's error envelope.
  #
  # Pass your own through `Client.new(http:)` to route through a proxy, add instrumentation, or
  # drive the client from a test.
  #
  # ## Why a fresh connection per request
  #
  # `Net::HTTP.start` opens a connection, yields, and closes it. Sharing one `Net::HTTP` instance
  # across callers is not a crash bug, it is **response cross-talk**: two threads interleave on
  # one socket and one receives the other's body. Inside a single process that is a
  # confidentiality bug, and it is exactly what `spec/concurrency_spec.rb` exists to catch.
  #
  # Connection reuse is therefore left to whoever needs it, with the reason stated: a correct
  # pool has to be safe under threads **and** under a fiber scheduler, which is more than a
  # scaffold should assume on a caller's behalf.
  class NetHttpAdapter
    # The HTTP verbs this adapter can issue, mapped to their `Net::HTTP` request classes.
    #
    # A frozen table rather than `const_get` on a caller-supplied string, which would turn a
    # method name into an arbitrary constant lookup.
    METHODS = {
      "GET" => Net::HTTP::Get,
      "POST" => Net::HTTP::Post,
      "PATCH" => Net::HTTP::Patch,
      "DELETE" => Net::HTTP::Delete
    }.freeze

    # Errors `Net::HTTP` raises when no response was produced. Each becomes a {ConnectionError}.
    TRANSPORT_ERRORS = [
      IOError,
      SocketError,
      SystemCallError,
      Timeout::Error,
      OpenSSL::SSL::SSLError,
      Net::HTTPBadResponse,
      Net::ProtocolError
    ].freeze

    # @param timeout [Integer, Float] the open and read timeout in seconds.
    def initialize(timeout: Config::DEFAULT_TIMEOUT)
      @timeout = timeout
      freeze
    end

    # Perform one HTTP round trip.
    #
    # @param method [String] the HTTP method; must be a key of {METHODS}.
    # @param url [String] the absolute URL to request.
    # @param headers [Hash{String => String}] the request headers.
    # @param body [String, nil] the already-serialized request body.
    # @return [HttpResponse] the response.
    # @raise [ConnectionError] when the request produced no response.
    def call(method:, url:, headers:, body: nil)
      uri = URI.parse(url)
      # `Config#build_url` only ever produces a URL with a host, but this adapter is public and
      # can be driven directly, so the guard is real rather than defensive noise.
      host = uri.hostname
      raise ConfigurationError, "URL has no host: #{url.inspect}" if host.nil?

      request = build_request(method, uri, headers, body)

      Net::HTTP.start(host, uri.port, use_ssl: uri.scheme == "https",
                                      open_timeout: @timeout, read_timeout: @timeout) do |http|
        to_response(http.request(request))
      end
    rescue *TRANSPORT_ERRORS => e
      raise ConnectionError, "#{e.class}: #{e.message}"
    end

    private

    # @return [Net::HTTPRequest] the request object for a method, URL, headers and body.
    def build_request(method, uri, headers, body)
      request_class = METHODS.fetch(method.upcase) do
        raise ConfigurationError, "unsupported HTTP method #{method.inspect}"
      end
      request = request_class.new(uri)
      headers.each { |name, value| request[name] = value }
      request.body = body unless body.nil?
      request
    end

    # @return [HttpResponse] the adapter-neutral view of a `Net::HTTPResponse`.
    def to_response(raw)
      headers = raw.each_header.to_h { |name, value| [name.downcase, value] }
      HttpResponse.new(status: raw.code.to_i, headers: headers, body: raw.body.to_s)
    end
  end
end
