# frozen_string_literal: true

require_relative "mailkube/version"
require_relative "mailkube/errors"
require_relative "mailkube/logging"
require_relative "mailkube/types"
require_relative "mailkube/types/scheduled_emails"
require_relative "mailkube/types/scheduled_acks"
require_relative "mailkube/serialization"
require_relative "mailkube/config"
require_relative "mailkube/transport"
require_relative "mailkube/net_http_adapter"
require_relative "mailkube/resources/emails"
require_relative "mailkube/resources/scheduled_email_requests"
require_relative "mailkube/resources/scheduled_emails"
require_relative "mailkube/client"
require_relative "mailkube/events/node"
require_relative "mailkube/events/contexts"
require_relative "mailkube/events/payloads"
require_relative "mailkube/events/envelopes"
require_relative "mailkube/events/registry"
require_relative "mailkube/webhooks"

# mailkube-ruby: The official Ruby SDK for mailkube
#
#     client = Mailkube.new                      # reads MAILKUBE_API_KEY
#     email = client.emails.send(
#       from: "Acme <hello@yourdomain.com>",
#       to: "customer@example.com",
#       subject: "Hello world",
#       html: "<p>It works!</p>"
#     )
#     email.id
#
# Errors form a hierarchy under {Error}, so rescue the category you care about:
#
#     begin
#       client.emails.send(...)
#     rescue Mailkube::RateLimitError => e
#       sleep(e.retry_after || 1)
#     end
#
# The conventions every mailkube SDK shares are in `.rules/SDK_CONTRACT.md`; how they are
# realized in Ruby is in `.rules/SDK_DESIGN.md`.
module Mailkube
  # The API base URL used when nothing else is configured.
  DEFAULT_BASE_URL = "https://api.mailkube.com/mta/v1/"

  # Create a {Client}. Sugar for `Mailkube::Client.new`, which is what most callers want.
  #
  # @param options [Hash] forwarded verbatim to {Client#initialize}.
  # @return [Client] the new client.
  def self.new(**options) = Client.new(**options)

  # Turn SDK request logging on. Sugar for {Logging.enable!}.
  #
  # The device is anything responding to `#write(String)`, so an application passes its own
  # logger rather than being handed one:
  #
  #     Mailkube.enable_logging(device: Rails.logger)
  #
  # @param device [#write] where to write; defaults to `$stderr`.
  # @return [#write] the device now in use.
  def self.enable_logging(device: $stderr) = Logging.enable!(device: device)
end

# Honour `MAILKUBE_LOG` at load, so a deployment can turn logging on without a code change.
Mailkube::Logging.enable_from_env
