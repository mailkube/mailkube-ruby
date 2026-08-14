# frozen_string_literal: true

# The error taxonomy: one base class, one class per category, and the table that selects them.
module Mailkube
  # Base class for every error this gem raises.
  #
  # Rescue this to catch anything the SDK can raise, or a subclass to branch on the category.
  # Ruby's idiom is an exception hierarchy rather than Go's sentinel values, so this mirrors the
  # python, node and PHP SDKs one-for-one; the categories, and the status that selects each, are
  # identical across all of them.
  class Error < StandardError; end

  # Raised when no API key is available, or configuration is otherwise unusable.
  class ConfigurationError < Error; end

  # Raised on a transport-level failure with no HTTP response: DNS, TCP, TLS or timeout.
  class ConnectionError < Error; end

  # Raised when a webhook signature or its timestamp cannot be verified.
  class SignatureVerificationError < Error; end

  # Raised for any non-2xx response, carrying the API's error envelope.
  #
  # Rescue a subclass to branch on the category, and read the attributes for the detail. The
  # envelope's `name` stays a plain string, so a value this release has never heard of is
  # reported verbatim rather than coerced.
  class APIError < Error
    # @return [String] the machine-readable name from the envelope, e.g. `quota_exceeded`.
    attr_reader :error_name
    # @return [Integer] the HTTP status code.
    attr_reader :status_code
    # @return [Hash] the decoded response body, or an empty hash.
    attr_reader :body
    # @return [Integer, nil] the Retry-After header in seconds, when the server sent one.
    attr_reader :retry_after
    # @return [String, nil] the server's request id, to quote to support.
    attr_reader :request_id

    # There is deliberately one base constructor taking the whole envelope, and no subclass
    # overrides it. Eight subclasses each repeating an argument list is how a duplication gate
    # starts failing and how two categories start reporting different fields.
    def initialize(message = nil, error_name: "", status_code: 0, body: {}, retry_after: nil, request_id: nil)
      super(message || (error_name.empty? ? "HTTP #{status_code}" : error_name))
      @error_name = error_name
      @status_code = status_code
      @body = body
      @retry_after = retry_after
      @request_id = request_id
    end
  end

  # HTTP 400: the request envelope was invalid.
  class BadRequestError < APIError; end

  # HTTP 403: authentication failed, or the key is forbidden from this action.
  class AuthenticationError < APIError; end

  # HTTP 404: a referenced resource was not found.
  class NotFoundError < APIError; end

  # HTTP 409: an idempotency conflict. The same key was reused with a different payload.
  class ConflictError < APIError; end

  # HTTP 422: the request was rejected by a send-policy check.
  class InvalidRequestError < APIError; end

  # HTTP 429: the rate limit was exceeded. Read {APIError#retry_after} before retrying.
  class RateLimitError < APIError; end

  # HTTP 5xx: an unexpected server error. Safe to retry with backoff.
  class ServerError < APIError; end

  # The documented values of the error envelope's `name` field.
  #
  # These are constants for discoverability, **not** a closed set: {APIError#error_name} stays a
  # plain String, so a name this release has never heard of is reported verbatim instead of
  # crashing an older client. The list tracks the public error reference and the other SDKs; add a
  # constant when the API adds a name.
  module ErrorName
    APPLICATION_ERROR = "application_error"
    BODY_CONTENT_REJECTED = "body_content_rejected"
    BROWSER_NOT_ALLOWED = "browser_not_allowed"
    CONCURRENT_IDEMPOTENT_REQUESTS = "concurrent_idempotent_requests"
    FROM_DOMAIN_NOT_ALLOWED = "from_domain_not_allowed"
    INVALID_API_KEY = "invalid_api_key"
    INVALID_ATTACHMENT = "invalid_attachment"
    INVALID_FROM_ADDRESS = "invalid_from_address"
    INVALID_IDEMPOTENCY_KEY = "invalid_idempotency_key"
    INVALID_IDEMPOTENT_REQUEST = "invalid_idempotent_request"
    INVALID_REQUEST_BODY = "invalid_request_body"
    LINK_REPUTATION_BLOCKED = "link_reputation_blocked"
    MAX_MESSAGE_SIZE_EXCEEDED = "max_message_size_exceeded"
    MAX_RECIPIENTS_EXCEEDED = "max_recipients_exceeded"
    METHOD_NOT_ALLOWED = "method_not_allowed"
    MISSING_REQUIRED_FIELD = "missing_required_field"
    MISSING_REQUIRED_VARIABLE = "missing_required_variable"
    MISSING_USER_AGENT = "missing_user_agent"
    NOT_ACCEPTABLE = "not_acceptable"
    QUOTA_EXCEEDED = "quota_exceeded"
    RATE_LIMIT_EXCEEDED = "rate_limit_exceeded"
    SCHEDULED_EMAIL_NOT_FOUND = "scheduled_email_not_found"
    SCHEDULED_EMAIL_NOT_PENDING = "scheduled_email_not_pending"
    SCHEDULING_NOT_INCLUDED = "scheduling_not_included"
    TEMPLATE_NOT_FOUND = "template_not_found"
    TEMPLATE_NOT_PUBLISHED = "template_not_published"
    TOPIC_DISABLED = "topic_disabled"
    TOPIC_NOT_FOUND = "topic_not_found"
    UNSUPPORTED_MEDIA_TYPE = "unsupported_media_type"
    VALIDATION_ERROR = "validation_error"
  end

  # Maps an HTTP status to its error class. Any other 5xx is {ServerError}; the rest {APIError}.
  STATUS_ERRORS = {
    400 => BadRequestError,
    403 => AuthenticationError,
    404 => NotFoundError,
    409 => ConflictError,
    422 => InvalidRequestError,
    429 => RateLimitError
  }.freeze

  # Returns the error class for an HTTP status.
  #
  # @param status [Integer] the HTTP status code.
  # @return [Class] the {APIError} subclass to raise.
  def self.error_class_for(status)
    return STATUS_ERRORS.fetch(status) if STATUS_ERRORS.key?(status)
    return ServerError if status >= 500

    APIError
  end
end
