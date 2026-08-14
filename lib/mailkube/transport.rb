# frozen_string_literal: true

require "json"

module Mailkube
  # A fully-built request, ready to send.
  #
  # @api private This is internal plumbing, not part of the supported surface. Build requests by
  #   calling a resource verb; the shape here may change in a minor release.
  #
  # `path` is relative to the base URL, or an absolute URL the API itself issued (a pagination
  # link). {Config#build_url} refuses an absolute URL off the configured origin.
  class RequestSpec < Data.define(:path, :method, :body, :params, :headers)
    # @param path [String] the path or absolute URL to request.
    # @param method [String] the HTTP method.
    # @param body [Hash, nil] the JSON request body, or nil for a body-less request.
    # @param params [Hash{String => String}] query parameters, already rendered to strings by
    #   {Serialization.query}. Empty means no query string at all, not an empty one.
    # @param headers [Hash{String => String}] per-request headers, merged over the defaults.
    def initialize(path:, method: "POST", body: nil, params: {}, headers: {}) = super
  end

  # One HTTP response, in the shape every adapter returns.
  #
  # `headers` are stored exactly as the adapter supplied them, and read through {#header}, which
  # matches case-insensitively as HTTP requires.
  #
  # Unlike the rest of this file, this class **is** public: it is the return type of the `http:`
  # adapter contract, so any adapter you write has to construct one.
  class HttpResponse < Data.define(:status, :headers, :body)
    # @param status [Integer] the HTTP status code.
    # @param headers [Hash{String => String}] response headers, in any casing.
    # @param body [String] the raw response body.
    def initialize(status:, headers: {}, body: "") = super

    # Look a header up, case-insensitively.
    #
    # Both sides are downcased, rather than downcasing the argument and indexing a map assumed to
    # be lowercase already. That assumption used to be this class's documented contract, and since
    # the class is **public** — the `http:` seam means third-party adapters construct it — it was
    # an invariant the SDK asked for and could not enforce. An adapter that passed `X-Request-Id`
    # through in the server's own casing produced a silent nil for every header the SDK reads,
    # which is exactly how the request id could have stayed empty even after the gateway started
    # sending it. A scan over a handful of pairs costs nothing and cannot be got wrong from
    # outside.
    #
    # @param name [String] a header name in any casing.
    # @return [String, nil] the header value, or nil when absent.
    def header(name)
      wanted = name.downcase
      headers.each { |key, value| return value if key.downcase == wanted }
      nil
    end
  end

  # Performs one HTTP round trip and turns the result into a model or a mapped error.
  #
  # @api private This is internal plumbing, not part of the supported surface. To swap out the HTTP
  #   layer, pass an adapter to `Client.new(http:)` — that seam **is** public, and it is documented
  #   in the README. Depending on this class directly is not supported.
  #
  # This is the layer that knows the API's error envelope and nothing about `Net::HTTP`: the
  # actual socket work lives behind the injected adapter (see {NetHttpAdapter}), which is what
  # lets the whole suite run without network access.
  #
  # A resource depends on the narrowest thing it needs, which in Ruby means an object responding
  # to the one verb it calls. `Resources::Emails` needs only `#send_email`. A new capability adds
  # a method here; it never widens an existing one.
  class Transport
    # @param config [Config] the resolved configuration.
    # @param adapter [#call] the HTTP adapter performing the round trip.
    def initialize(config, adapter)
      @config = config
      @adapter = adapter
      freeze
    end

    # Perform a send request and build the accepted-send result.
    #
    # @param spec [RequestSpec] the request to perform.
    # @return [Email] the accepted-send result.
    # @raise [APIError] on any non-2xx response.
    # @raise [ConnectionError] on a transport failure or timeout.
    def send_email(spec)
      response = perform(spec)
      payload = decode(response.body)
      id = payload["id"]
      raise APIError.new("expected a JSON body with an 'id'", status_code: response.status) unless id.is_a?(String)

      Email.new(
        id: id,
        message_id: payload["message_id"],
        idempotent_replayed: response.header("Idempotent-Replayed")&.downcase == "true",
        status: payload["status"],
        scheduled_at: payload["scheduled_at"],
        batch_id: payload["batch_id"]
      )
    end

    # Perform a request and return its decoded JSON object body.
    #
    # The second transport verb, and deliberately **not** a widening of the first: {#send_email}
    # builds one specific model out of a body plus a response header, which is a send concern.
    # This one hands back the decoded object and lets the resource name its model, which is what
    # keeps {Resources::Emails} depending on `#send_email` alone.
    #
    # It takes no model argument on purpose. Ruby has no generics and RBS cannot tie a class
    # argument to a return type, so a `request(spec, model)` form would make Steep prove generic
    # structural conformance for something the resource already knows statically. Naming the model
    # is a resource decision; decoding is this layer's.
    #
    # @param spec [RequestSpec] the request to perform.
    # @return [Hash{String => Object}] the decoded 2xx body.
    # @raise [APIError] on any non-2xx response, or a 2xx body that is not a JSON object.
    # @raise [ConnectionError] on a transport failure or timeout.
    def request_json(spec)
      response = perform(spec)
      payload = decode_object(response.body)
      raise APIError.new("expected a JSON object body", status_code: response.status) if payload.nil?

      payload
    end

    private

    # Perform the round trip, raising the mapped error for any non-2xx status.
    #
    # This is the single place a status becomes an exception, so every verb, present and future,
    # reports failures identically.
    #
    # @param spec [RequestSpec] the request to perform.
    # @return [HttpResponse] the 2xx response.
    def perform(spec)
      url = @config.build_url(spec.path, spec.params)
      headers = @config.default_headers.merge(spec.headers)
      Logging.request(spec.method, url, headers)
      response = @adapter.call(
        method: spec.method,
        url: url,
        headers: headers,
        body: spec.body.nil? ? nil : JSON.generate(spec.body)
      )
      Logging.response(response.status, url, response.header("X-Request-Id"))
      return response if (200..299).cover?(response.status)

      raise error_for(response)
    end

    # Build the exception for a non-2xx response.
    #
    # @param response [HttpResponse] the failed response.
    # @return [APIError] the exception to raise.
    def error_for(response)
      payload = decode(response.body)
      Mailkube.error_class_for(response.status).new(
        payload["message"],
        error_name: payload["name"].is_a?(String) ? payload["name"] : "",
        status_code: response.status,
        body: payload,
        retry_after: response.header("Retry-After")&.to_i,
        request_id: response.header("X-Request-Id")
      )
    end

    # Decode a body strictly: nil when it is empty, undecodable, or not a JSON *object*.
    #
    # Split out of {#decode} rather than inlined, because the two callers need opposite things
    # from the same parse: {#error_for} must stay lenient, so a malformed error body still maps by
    # status, and {#request_json} must not, so a 2xx that is not an object is reported rather than
    # silently becoming an empty model. One parse, two contracts.
    #
    # @param raw [String] the raw response body.
    # @return [Hash{String => Object}, nil] the decoded object, or nil.
    def decode_object(raw)
      return nil if raw.empty?

      decoded = JSON.parse(raw)
      decoded.is_a?(Hash) ? decoded : nil
    rescue JSON::ParserError
      nil
    end

    # Best-effort JSON decode: an empty or undecodable body becomes an empty hash, so a
    # malformed error response still maps by status.
    #
    # @param raw [String] the raw response body.
    # @return [Hash] the decoded object, or an empty hash.
    def decode(raw) = decode_object(raw) || {}
  end
end
