# frozen_string_literal: true

# Describe the API key this client authenticates with: its domain, organization, plan and
# send-quota usage. Nothing is sent, and the key itself is never printed.
#
#   export MAILKUBE_API_KEY=mk_...
#   ruby examples/credential_info.rb
#
# The key is checked exactly as a send checks it, so this is also how to verify a key before using
# it: a key that cannot send raises Mailkube::AuthenticationError (invalid_api_key). The call counts
# as a use of the key, and plan figures can be up to 30 seconds old.

require_relative "../lib/mailkube"

client = Mailkube.new # reads MAILKUBE_API_KEY

begin
  key = client.credential.info
rescue Mailkube::AuthenticationError => e
  abort("this key cannot send: #{e.error_name}")
end

puts "key #{key.key_id} (#{key.name}) sends for #{key.domain.name}"
puts "organization #{key.organization.name} (#{key.organization.alias})"
puts "allowed from #{key.allowed_source_ips.empty? ? "any address" : key.allowed_source_ips.join(", ")}"

# A plan without a daily limit lists the monthly quota only; an absent quota is no limit.
if key.plan.nil?
  puts "no subscription"
else
  puts "plan #{key.plan.name} (#{key.plan.status})"
  key.plan.quotas.each do |quota|
    puts "  #{quota.name}: #{quota.used} of #{quota.limit} recipients in #{quota.period}"
  end
end
