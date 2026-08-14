# frozen_string_literal: true

module Mailkube
  # The API client, and this gem's composition root.
  #
  # Create one and reuse it. It is frozen after construction and safe to share across threads
  # (and across fibers, where a scheduler is installed); `spec/concurrency_spec.rb` proves it
  # rather than asserting it.
  #
  #     client = Mailkube.new                      # reads MAILKUBE_API_KEY
  #     email = client.emails.send(
  #       from: "Acme <hello@yourdomain.com>",
  #       to: "customer@example.com",
  #       subject: "Hello world",
  #       html: "<p>It works!</p>"
  #     )
  #
  # There are deliberately no built-in retries. A {RateLimitError} carries `retry_after` and a
  # {ServerError} is safe to retry with backoff, so the calling application decides. Pass
  # `idempotency_key:` to make a retry safe.
  #
  # This client is **synchronous**, which is the contract's sync-only case: concurrency here is
  # the caller's concern rather than an API-surface decision. See `.rules/SDK_DESIGN.md`.
  class Client
    # @return [Resources::Emails] the emails namespace.
    attr_reader :emails
    # @return [Resources::ScheduledEmails] the scheduled-emails namespace.
    attr_reader :scheduled_emails

    # Create a client, resolving configuration from the arguments then the environment.
    #
    # @param api_key [String, nil] the API key; falls back to `MAILKUBE_API_KEY`.
    # @param base_url [String, nil] the API base URL; falls back to `MAILKUBE_BASE_URL`.
    # @param timeout [Integer, Float] the per-request open and read timeout in seconds.
    # @param http [#call, nil] an HTTP adapter to use instead of the built-in {NetHttpAdapter}.
    #   This is the dependency-inversion seam the test suite injects through; when supplied,
    #   `timeout` is the adapter's business rather than this client's.
    # @raise [ConfigurationError] when no API key is available.
    def initialize(api_key: nil, base_url: nil, timeout: Config::DEFAULT_TIMEOUT, http: nil)
      config = Config.new(api_key: api_key, base_url: base_url, timeout: timeout)
      transport = Transport.new(config, http || NetHttpAdapter.new(timeout: timeout))

      @config = config
      @emails = Resources::Emails.new(transport)
      @scheduled_emails = Resources::ScheduledEmails.new(transport)
      freeze
    end

    # @return [String] the resolved API base URL.
    def base_url = @config.base_url
  end
end
