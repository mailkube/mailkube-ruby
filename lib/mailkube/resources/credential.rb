# frozen_string_literal: true

module Mailkube
  module Resources
    # The client's own credential, reached as `client.credential`.
    #
    # It describes the API key the client was constructed with and holds no setter: a client takes
    # its key at construction and keeps it, which is what makes one instance safe to share across
    # threads. A second key is a second client.
    class Credential
      # @param transport [#request_json] the transport performing this resource's requests.
      def initialize(transport)
        @transport = transport
        freeze
      end

      # Describe the API key this client authenticates with: its domain, organization, source-IP
      # allowlist, plan and send-quota usage.
      #
      # The key is checked exactly as a send checks it, so a key that cannot send raises
      # {AuthenticationError} (`invalid_api_key`), which also makes this the way to verify a key.
      # The call counts as a use of the key. Plan and quota figures can be up to 30 seconds old.
      #
      # @return [APIKey] the calling API key.
      # @raise [APIError] on any non-2xx response.
      # @raise [ConnectionError] on a transport failure or timeout.
      def info
        APIKey.from(@transport.request_json(RequestSpec.new(path: "api-keys/me", method: "GET")))
      end
    end
  end
end
