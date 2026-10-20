# frozen_string_literal: true

module Mailkube
  # The API key the client authenticates with, as it describes itself.
  #
  # Returned by {Resources::Credential#info}. Timestamps stay the verbatim ISO-8601 strings the
  # server sent; call `Time.iso8601` yourself if you want objects. Plan and quota figures can be up
  # to 30 seconds old.
  class APIKey < Data.define(:object, :key_id, :name, :description, :created_at, :last_auth_at,
                             :allowed_source_ips, :domain, :organization, :plan)
    # @param object [String] the resource discriminator, always `api_key`.
    # @param key_id [String] the key's public identifier.
    # @param name [String] the key's name.
    # @param description [String, nil] the key's description.
    # @param created_at [String] when the key was created.
    # @param last_auth_at [String, nil] the key's last successful authentication, this call included.
    # @param allowed_source_ips [Array<String>] the CIDR networks the key may be used from; empty
    #   means any address.
    # @param domain [APIKeyDomain] the sending domain the key belongs to.
    # @param organization [APIKeyOrganization] the organization owning the domain.
    # @param plan [APIKeyPlan, nil] the organization's plan, nil when it has no subscription.
    def initialize(key_id:, object: "api_key", name: "", description: nil, created_at: "", last_auth_at: nil,
                   allowed_source_ips: [], domain: APIKeyDomain.new, organization: APIKeyOrganization.new,
                   plan: nil)
      super
    end

    # `plan` is the one field the API sends as null, meaning "no subscription", so it is decoded
    # only when present: an empty plan built from defaults would look like a real one.
    #
    # @param payload [Hash{String => Object}] the decoded `api_key` object.
    # @return [APIKey] the model.
    def self.from(payload)
      new(key_id: payload["key_id"], object: payload["object"] || "api_key", name: payload["name"] || "",
          description: payload["description"], created_at: payload["created_at"] || "",
          last_auth_at: payload["last_auth_at"], allowed_source_ips: payload["allowed_source_ips"] || [],
          domain: APIKeyDomain.from(payload["domain"]), organization: APIKeyOrganization.from(payload["organization"]),
          plan: payload["plan"] && APIKeyPlan.from(payload["plan"]))
    end
  end

  # The sending domain an API key belongs to.
  class APIKeyDomain < Data.define(:name)
    # @param name [String] the domain name, e.g. `example.com`.
    def initialize(name: "") = super

    # @param payload [Hash{String => Object}, nil] the decoded `domain` block.
    # @return [APIKeyDomain] the model.
    def self.from(payload) = new(name: (payload || {})["name"] || "")
  end

  # The organization owning an API key's domain.
  class APIKeyOrganization < Data.define(:name, :alias)
    # @param name [String] the organization's display name.
    # @param alias [String] the organization's short alias.
    def initialize(name: "", alias: "") = super

    # @param payload [Hash{String => Object}, nil] the decoded `organization` block.
    # @return [APIKeyOrganization] the model.
    def self.from(payload)
      block = payload || {}
      new(name: block["name"] || "", alias: block["alias"] || "")
    end
  end

  # The organization's plan, its status and its send quotas.
  #
  # `status` is a server-controlled string, deliberately not an enum. A plan without a daily limit
  # lists the monthly quota only: an absent quota is a missing limit, never a limit of zero.
  class APIKeyPlan < Data.define(:code, :name, :status, :quotas)
    # @param code [String] the plan's UUID.
    # @param name [String] the plan's name.
    # @param status [String] the subscription status, e.g. `active`.
    # @param quotas [Array<APIKeyQuota>] the send quotas the plan carries.
    def initialize(code: "", name: "", status: "", quotas: []) = super

    # @param payload [Hash{String => Object}] the decoded `plan` block.
    # @return [APIKeyPlan] the model.
    def self.from(payload)
      new(code: payload["code"] || "", name: payload["name"] || "", status: payload["status"] || "",
          quotas: (payload["quotas"] || []).map { |quota| APIKeyQuota.from(quota) })
    end
  end

  # One send quota of the plan: its limit and what the current period has used, in recipients.
  class APIKeyQuota < Data.define(:name, :limit, :used, :remaining, :period)
    # @param name [String] which quota, e.g. `emails_per_day` or `emails_per_month`; a
    #   server-controlled string, deliberately not an enum.
    # @param limit [Integer] the plan's limit for the period.
    # @param used [Integer] recipients sent to so far in the period.
    # @param remaining [Integer] recipients left in the period.
    # @param period [String] the UTC day (`2026-10-19`) or month (`2026-10`) the figures count.
    def initialize(name: "", limit: 0, used: 0, remaining: 0, period: "") = super

    # @param payload [Hash{String => Object}] one decoded quota.
    # @return [APIKeyQuota] the model.
    def self.from(payload)
      new(name: payload["name"] || "", limit: payload["limit"] || 0, used: payload["used"] || 0,
          remaining: payload["remaining"] || 0, period: payload["period"] || "")
    end
  end
end
