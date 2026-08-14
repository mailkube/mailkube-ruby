# frozen_string_literal: true

require "time"
require "erb/util"

module Mailkube
  # How a Ruby value becomes JSON, a query-string parameter, or a path segment.
  #
  # One home for every "how does this go on the wire" decision, shared by every resource. Nothing
  # here validates: the server is the authority on what a value means, and its error names are
  # richer than anything the SDK would reproduce. These functions only make values transmissible.
  module Serialization
    # Render an instant for a JSON body, passing an already-formatted string through.
    #
    # Returns nil for nil on purpose: that is what lets a request body be one hash literal followed
    # by a single `compact`, and why an unset field is absent from the wire rather than sent as
    # null. Compare {query_value}, which can never return nil.
    #
    # @param value [Time, String, nil] the caller's instant.
    # @return [String, nil] the ISO-8601 rendering, or nil.
    def self.to_iso(value) = value.is_a?(Time) ? value.iso8601 : value

    # Render one query-string parameter, **always** as a String.
    #
    # A list becomes a comma-joined value rather than a repeated parameter: the API accepts both,
    # and a flat `Hash[String, String]` keeps the transport seam simple in every SDK that mirrors
    # this design. A query string has no types, which is why this cannot just call {to_iso}: that
    # would hand back the Integer `2` for `page: 2`.
    #
    # @param value [Object] a scalar, a Time, or an array of either.
    # @return [String] the parameter's string form.
    def self.query_value(value)
      return value.map { |item| query_scalar(item) }.join(",") if value.is_a?(Array)

      query_scalar(value)
    end

    # @param value [Object] one scalar parameter value.
    # @return [String] its string form.
    def self.query_scalar(value) = value.is_a?(Time) ? value.iso8601 : value.to_s
    private_class_method :query_scalar

    # Render a whole filter set for the query string, dropping the filters the caller omitted.
    #
    # `compact` is what makes both wire rules true in one pass, at a cyclomatic complexity of 1:
    # an omitted filter never reaches the wire, and no filters at all yields an empty hash, which
    # {Config#build_url} turns into no query string rather than a bare `?`.
    #
    # @param filters [Hash{Symbol => Object}] the caller's filters, nils included.
    # @return [Hash{String => String}] the query parameters.
    #
    # Accumulated into an annotated hash rather than returned from `to_h { [k, v] }`, because Steep
    # infers a two-element array literal in block-body position as `Array[String]`, not as the
    # `[String, String]` tuple `to_h`'s signature demands, and reports a `BlockBodyTypeMismatch`
    # that no annotation on the block can settle.
    def self.query(filters)
      rendered = {} #: Hash[String, String]
      filters.compact.each { |name, value| rendered[name.to_s] = query_value(value) }
      rendered
    end

    # Escape one interpolated path segment.
    #
    # `ERB::Util.url_encode`, and specifically **not** `CGI.escape` or
    # `URI.encode_www_form_component`: those render a space as `+`, which is the form-encoding rule
    # for a query string, not the percent-encoding rule for a path segment. It is also not
    # cosmetic — an identifier carrying an encoded `/` or `?` would otherwise re-target the request
    # at a different route. `erb` is a default gem on every supported Ruby, so this costs no
    # dependency.
    #
    # @param value [String] the identifier to interpolate.
    # @return [String] the percent-encoded segment.
    def self.escape_segment(value) = ERB::Util.url_encode(value)

    # @param attachments [Array<Attachment>, nil] the attachments as supplied.
    # @return [Array<Hash>, nil] JSON-serializable attachments, or nil when there are none.
    def self.encode_attachments(attachments)
      return nil if attachments.nil? || attachments.empty?

      attachments.map do |item|
        # `[bytes].pack("m0")` rather than `Base64.strict_encode64`: `base64` is a bundled gem from
        # Ruby 3.4, so requiring it without declaring it fails under Bundler, and declaring it would
        # cost this gem its zero-dependency claim.
        entry = { "filename" => item.filename, "content" => [item.content].pack("m0") }
        entry["content_type"] = item.content_type unless item.content_type.nil?
        entry
      end
    end

    # @param tags [Array<Tag>, nil] the tags as supplied.
    # @return [Array<Hash>, nil] JSON-serializable tags, or nil when there are none.
    def self.encode_tags(tags)
      return nil if tags.nil? || tags.empty?

      tags.map { |tag| { "name" => tag.name, "value" => tag.value } }
    end
  end
end
