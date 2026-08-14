# frozen_string_literal: true

require "time"

# Every "how does this go on the wire" decision lives in one module, so this file is where the
# encoding rules are pinned. The resources' own specs assert that a verb *uses* these; they do not
# re-assert what the encodings are.
RSpec.describe Mailkube::Serialization do
  describe "rendering an instant for a JSON body" do
    it "renders a Time as ISO-8601" do
      expect(described_class.to_iso(Time.utc(2026, 8, 20, 7, 0, 0))).to eq("2026-08-20T07:00:00Z")
    end

    it "passes an already-formatted string through, rather than reinterpreting server data" do
      expect(described_class.to_iso("2026-08-20T07:00:00Z")).to eq("2026-08-20T07:00:00Z")
    end

    it "keeps nil as nil, so the body's single compact can drop the field" do
      expect(described_class.to_iso(nil)).to be_nil
    end
  end

  describe "rendering one query parameter" do
    it "renders a list as one comma-joined value rather than a repeated parameter" do
      expect(described_class.query_value(%w[scheduled canceled])).to eq("scheduled,canceled")
    end

    it "renders a Time inside a list as ISO-8601 too" do
      expect(described_class.query_value([Time.utc(2026, 8, 20, 7, 0, 0)])).to eq("2026-08-20T07:00:00Z")
    end

    it "renders a Time as ISO-8601" do
      expect(described_class.query_value(Time.utc(2026, 8, 20, 7, 0, 0))).to eq("2026-08-20T07:00:00Z")
    end

    it "always returns a String, because a query string has no types" do
      expect(described_class.query_value(2)).to eq("2")
    end
  end

  describe "rendering a whole filter set" do
    it "drops the filters the caller omitted rather than sending them empty" do
      params = described_class.query(status: "scheduled", batch_id: nil, page: nil)

      expect(params).to eq("status" => "scheduled")
    end

    it "yields an empty hash when nothing is filtered, which becomes no query string at all" do
      expect(described_class.query(status: nil, page: nil)).to eq({})
    end

    it "stringifies the keys, since the transport seam carries a flat string hash" do
      expect(described_class.query(page: 2).keys).to eq(["page"])
    end
  end

  describe "escaping a path segment" do
    it "percent-encodes a separator so an identifier cannot re-target the request at another route" do
      expect(described_class.escape_segment("../batches/x?page=9")).to eq("..%2Fbatches%2Fx%3Fpage%3D9")
    end

    it "encodes a space as %20, not as +, because this is a path and not a form field" do
      expect(described_class.escape_segment("a b")).to eq("a%20b")
    end

    it "leaves the unreserved set alone" do
      expect(described_class.escape_segment("aZ0-_.~")).to eq("aZ0-_.~")
    end
  end

  describe "encoding attachments" do
    it "base64-encodes the raw bytes" do
      encoded = described_class.encode_attachments([Mailkube::Attachment.new(filename: "a.txt", content: "hi")])

      expect(encoded).to eq([{ "filename" => "a.txt", "content" => "aGk=" }])
    end

    it "includes a content type only when the caller set one" do
      attachment = Mailkube::Attachment.new(filename: "a.txt", content: "hi", content_type: "text/plain")

      expect(described_class.encode_attachments([attachment]).first).to include("content_type" => "text/plain")
    end

    it "returns nil for no attachments, so the field is absent from the wire" do
      expect(described_class.encode_attachments([])).to be_nil
      expect(described_class.encode_attachments(nil)).to be_nil
    end
  end

  describe "encoding tags" do
    it "renders each tag as a name/value pair" do
      encoded = described_class.encode_tags([Mailkube::Tag.new(name: "campaign", value: "welcome")])

      expect(encoded).to eq([{ "name" => "campaign", "value" => "welcome" }])
    end

    it "keeps a blank value, which the API allows" do
      expect(described_class.encode_tags([Mailkube::Tag.new(name: "campaign")]).first).to eq(
        "name" => "campaign", "value" => ""
      )
    end

    it "returns nil for no tags, so the field is absent from the wire" do
      expect(described_class.encode_tags([])).to be_nil
      expect(described_class.encode_tags(nil)).to be_nil
    end
  end
end
