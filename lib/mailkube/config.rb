# frozen_string_literal: true

require "uri"

module Mailkube
  # Resolved client configuration: the key, the origin, the timeout and the default headers.
  #
  # @api private This is internal plumbing, not part of the supported surface. Configure the client
  #   through `Client.new` or the environment; both are documented in the README.
  #
  # This is the only place configuration is read, and the only place a URL is built. Keeping the
  # origin guard here rather than in a resource protects every future link-following feature for
  # free. Instances are frozen: a client that cannot be reconfigured after construction is a
  # client that cannot develop a concurrency bug.
  class Config
    # Environment variable holding the API key.
    ENV_API_KEY = "MAILKUBE_API_KEY"
    # Environment variable overriding the API base URL.
    ENV_BASE_URL = "MAILKUBE_BASE_URL"
    # Per-request timeout in seconds when the caller does not set one.
    DEFAULT_TIMEOUT = 30

    # @return [String] the resolved API base URL, always ending in a slash.
    attr_reader :base_url
    # @return [Integer, Float] the per-request timeout in seconds.
    attr_reader :timeout

    # Resolve configuration from the arguments, then the environment, then the defaults.
    #
    # @param api_key [String, nil] the API key; falls back to `MAILKUBE_API_KEY`.
    # @param base_url [String, nil] the API base URL; falls back to `MAILKUBE_BASE_URL`.
    # @param timeout [Integer, Float] the per-request timeout in seconds.
    # @raise [ConfigurationError] when no API key is available.
    def initialize(api_key: nil, base_url: nil, timeout: DEFAULT_TIMEOUT)
      key = api_key || ENV.fetch(ENV_API_KEY, nil)
      raise ConfigurationError, "no API key provided: pass api_key: or set #{ENV_API_KEY}" if key.nil? || key.empty?

      @api_key = key
      @base_url = base_url || ENV.fetch(ENV_BASE_URL, nil) || Mailkube::DEFAULT_BASE_URL
      @timeout = timeout
      freeze
    end

    # The auth and non-browser identification headers sent on every request.
    #
    # The User-Agent is required: the API rejects a request without one. It reports
    # Mailkube::VERSION, which the gemspec also reads, so it cannot drift from the released
    # version.
    #
    # @return [Hash{String => String}] the default headers.
    def default_headers
      {
        "Authorization" => "Bearer #{@api_key}",
        "User-Agent" => "mailkube-ruby/#{VERSION}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
    end

    # Join a relative path onto the base URL, attach the query, and refuse any absolute URL off
    # the base URL's origin.
    #
    # Every request carries the Authorization header, so following a link that names a foreign
    # host would hand that host the API key.
    #
    # The query is attached **after** the origin check and only when there is one, so an absolute
    # page link the API issued keeps its own query untouched and an unfiltered listing produces no
    # `?` at all. `URI.encode_www_form` — not {Serialization.escape_segment} — is correct here: a
    # space in a query value is `+`, and a space in a path segment is `%20`.
    #
    # @param path [String] a relative path, or an absolute URL the API itself issued.
    # @param params [Hash{String => String}] query parameters, already rendered to strings by
    #   {Serialization.query}.
    # @return [String] the absolute URL to request.
    # @raise [ConfigurationError] when the result is not on the configured origin.
    def build_url(path, params = {})
      base = URI.parse(@base_url)
      resolved = base.merge(path)
      unless resolved.scheme == base.scheme && resolved.host == base.host && resolved.port == base.port
        raise ConfigurationError, "refusing to follow #{resolved}: it is not on the configured API origin"
      end

      resolved.query = URI.encode_www_form(params) unless params.empty?
      resolved.to_s
    rescue URI::InvalidURIError, URI::InvalidComponentError => e
      raise ConfigurationError, "invalid URL #{path.inspect}: #{e.message}"
    end
  end
end
