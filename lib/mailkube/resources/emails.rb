# frozen_string_literal: true

module Mailkube
  module Resources
    # The `emails` namespace, reached as `client.emails`.
    #
    # This is the worked example every new resource copies. Note what it does *not* do: it holds
    # no configuration, performs no I/O, and never requires `net/http`. It depends only on an
    # object responding to the one verb it calls.
    class Emails
      # @param transport [#send_email] the transport performing this resource's requests.
      def initialize(transport)
        @transport = transport
        freeze
      end

      # Send an email.
      #
      # Supply `html` and/or `text` for a raw send, or `template_id` for a saved template.
      # `idempotency_key` travels as the `Idempotency-Key` header rather than in the body.
      # Passing `scheduled_at` schedules the send instead of delivering it now; the result then
      # reports {Email#scheduled?}.
      #
      # This method shadows `Object#send` **on this object only**, which is deliberate: every
      # mailkube SDK spells the verb `emails.send`, and a Ruby-only name would break that. Use
      # `__send__` if you need reflective dispatch on a resource.
      #
      # @param from [String] the sender address, optionally with a display name.
      # @param to [String, Array<String>] the recipient address or addresses.
      # @param subject [String] the subject line.
      # @param html [String, nil] the HTML body, for a raw-content send.
      # @param text [String, nil] the plain-text body, for a raw-content send.
      # @param cc [Array<String>, nil] carbon-copy recipients.
      # @param bcc [Array<String>, nil] blind carbon-copy recipients.
      # @param reply_to [String, Array<String>, nil] the Reply-To addresses.
      # @param headers [Hash{String => String}, nil] custom message headers.
      # @param attachments [Array<Attachment>, nil] the file attachments.
      # @param tags [Array<Tag>, nil] free-form name/value tags forwarded to the server.
      # @param template_id [String, nil] the UUID of a saved template to render.
      # @param template_version [String, nil] a template version number, or "latest".
      # @param variables [Hash, nil] values for the template's placeholders.
      # @param topic [String, nil] the mailing-list topic slug this send is attributed to.
      # @param idempotency_key [String, nil] sent as the `Idempotency-Key` header.
      # @param scheduled_at [Time, String, nil] schedules the send instead of sending now.
      # @param batch_id [String, nil] groups several scheduled sends.
      # @return [Email] the accepted-send result.
      # @raise [APIError] on any non-2xx response.
      # @raise [ConnectionError] on a transport failure or timeout.
      def send(from:, to:, subject:, html: nil, text: nil, cc: nil, bcc: nil, reply_to: nil, headers: nil,
               attachments: nil, tags: nil, template_id: nil, template_version: nil, variables: nil,
               topic: nil, idempotency_key: nil, scheduled_at: nil, batch_id: nil)
        # One hash literal, then a single `compact`, rather than a chain of `body["x"] = x if x`.
        # That keeps this method's cyclomatic complexity at 1 no matter how many optional fields
        # the API grows, and is why an unset field is absent from the wire rather than null.
        body = {
          "from" => from, "to" => to, "subject" => subject,
          "html" => html, "text" => text, "cc" => cc, "bcc" => bcc,
          "reply_to" => reply_to, "headers" => headers,
          "attachments" => Serialization.encode_attachments(attachments),
          "tags" => Serialization.encode_tags(tags),
          "template_id" => template_id, "template_version" => template_version,
          "variables" => variables, "topic" => topic,
          "scheduled_at" => Serialization.to_iso(scheduled_at), "batch_id" => batch_id
        }.compact

        @transport.send_email(RequestSpec.new(path: "emails", body: body, headers: idempotency(idempotency_key)))
      end

      private

      # Build the body as one hash literal and drop the nils in a single pass, rather than a
      # chain of `body["x"] = x if x`. That keeps this method's cyclomatic complexity at 1 no
      # matter how many optional fields the API grows, and is why an unset field is absent from
      # the wire rather than sent as null.
      #
      # @param key [String, nil] the caller's idempotency key.
      # @return [Hash{String => String}] the per-request headers.
      def idempotency(key) = key.nil? ? {} : { "Idempotency-Key" => key }
    end
  end
end
