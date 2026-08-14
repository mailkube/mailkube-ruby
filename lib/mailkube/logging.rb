# frozen_string_literal: true

module Mailkube
  # Opt-in request logging: silent by default, and never a secret on the way out.
  #
  # Deliberately **not** built on stdlib `Logger`. `logger` stopped being a default gem in Ruby
  # 4.0, so `require "logger"` inside this gem raises under Bundler on a Ruby this gem supports,
  # and declaring it would cost the gem its zero-dependency claim — the same trap that keeps
  # `Base64` out of {Serialization}. A library also has no business installing handlers, levels or
  # formatters on its host's behalf.
  #
  # So the sink is any object responding to `#write(String)`: `$stderr`, a `File`, a `StringIO`,
  # or a two-line shim over your application's own logger. That is the same dependency-inversion
  # seam `Client.new(http:)` already uses, and it is what makes `Mailkube.enable_logging(device:
  # Rails.logger)` work without this gem knowing what Rails is.
  #
  # This is the one piece of mutable module state in the gem. {enable!} and {disable!} are
  # boot-time calls from the main thread; assigning one object reference is atomic, and no request
  # path ever writes here.
  module Logging
    # Environment variable that turns logging on without a code change. It holds a **level**.
    ENV_LEVEL = "MAILKUBE_LOG"
    # The `MAILKUBE_LOG` values verbose enough to let this SDK's records through.
    #
    # `MAILKUBE_LOG` is a level, not a flag, in every mailkube SDK. This one emits exactly one
    # class of record, the request/response trace, and that record is debug-level — so a level
    # more selective than debug must silence it. `MAILKUBE_LOG=warning` is a working way to say
    # "logs, but not from the SDK", and it has to keep working here or the variable means
    # something different in Ruby than in python, node, Go and PHP.
    VERBOSE_LEVELS = %w[trace debug all].freeze
    # The headers whose values are masked before anything is written.
    SENSITIVE_HEADERS = %w[authorization idempotency-key].freeze
    # What a masked header value is replaced with.
    REDACTION = "***"

    @device = nil

    # @return [#write, nil] where SDK logging is written, or nil when it is off.
    def self.device = @device

    # Turn logging on.
    #
    # @param device [#write] where to write; anything responding to `#write(String)`.
    # @return [#write] the device now in use.
    def self.enable!(device: $stderr) = @device = device

    # Turn logging back off. The inverse of {enable!}, for a suite that turned it on.
    #
    # @return [nil] always.
    def self.disable! = @device = nil

    # Turn logging on from the environment, when `MAILKUBE_LOG` names a level of {VERBOSE_LEVELS}.
    #
    # Called once from `mailkube.rb`, so a deployment can turn logging on without a code change.
    # It takes the environment as an argument rather than reading `ENV` inline because a bare `if`
    # at the bottom of a file runs exactly once at load: no spec could reach its second branch, and
    # the branch-coverage gate would then be paying for a line nobody can test.
    #
    # An unrecognized value leaves logging **off** rather than raising. This runs at `require`
    # time, and no environment variable should be able to make `require "mailkube"` fail.
    #
    # @param env [Hash] the environment to read.
    # @return [#write, nil] the device now in use, or nil when the level does not admit this SDK.
    def self.enable_from_env(env = ENV)
      level = env[ENV_LEVEL]
      return nil unless VERBOSE_LEVELS.include?(level.to_s.strip.downcase)

      enable!
    end

    # A copy of `headers` with every secret value masked, safe to write anywhere.
    #
    # @param headers [Hash{String => String}] the headers about to be logged.
    # @return [Hash{String => String}] the redacted copy; the caller's hash is not modified.
    #
    # Accumulated into an annotated hash rather than returned from `to_h { [k, v] }`, for the same
    # reason as {Serialization.query}: Steep types a two-element array literal in block-body
    # position as `Array[String]`, not as the tuple `to_h` declares.
    def self.redact(headers)
      masked = {} #: Hash[String, String]
      headers.each { |name, value| masked[name] = SENSITIVE_HEADERS.include?(name.downcase) ? REDACTION : value }
      masked
    end

    # Log one outgoing request, with its headers redacted.
    #
    # The `&.` is not a nil-check bolted onto a log line: it **is** "silent by default", and it is
    # why {redact} costs nothing for the callers who never enable logging — which is what lets this
    # call sit on the request path at all.
    #
    # @param method [String] the HTTP method.
    # @param url [String] the absolute URL.
    # @param headers [Hash{String => String}] the merged request headers.
    # @return [void]
    def self.request(method, url, headers)
      @device&.write("mailkube > #{method} #{url} #{redact(headers)}\n")
    end

    # Log one response, including the server's request id when it sent one.
    #
    # The id is what makes a support ticket traceable: the customer finds the failing call in
    # their own logs and quotes the same value the API recorded. It is an id, not content — no
    # recipient, subject or body reaches a log record here or anywhere else in this module.
    #
    # @param status [Integer] the HTTP status code.
    # @param url [String] the absolute URL.
    # @param request_id [String, nil] the `X-Request-Id` header, when the response carried one.
    # @return [void]
    def self.response(status, url, request_id = nil)
      @device&.write("mailkube < #{status} #{url}#{request_id.nil? ? "" : " request_id=#{request_id}"}\n")
    end
  end
end
