# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/http/media_type"
require_relative "../../../lib/dexpace/instrumentation/preview"

# Exercises: OBS-38
#
# The chapter's three cases, and none of them ASCII: the §3.1 decode-sentence finding's own point
# is that an ASCII-only fixture passes under the bug. The media type is phase 1's real
# Dexpace::MediaType, whose #charset is already nil for an absent or unrecognised charset
# (HTTP-24), which is what keeps Encoding.find unreachable from here.
class DexpaceInstrumentationPreviewTest < DexpaceTestCase
  Preview = Dexpace::Instrumentation::Preview
  MediaType = Dexpace::MediaType

  test "OBS-38: empty input yields an empty preview, whatever the media type" do
    assert_equal("", Preview.render("", media_type: nil))
    assert_equal("", Preview.render("".b, media_type: MediaType.parse("text/plain")))
    assert_equal("", Preview.render(nil, media_type: MediaType.parse("image/png")))
  end

  test "OBS-38: a non-text payload, and one with no media type, gets the size-only marker" do
    bytes = "raw\x00binary\xFF".b

    assert_equal(11, bytes.bytesize)
    assert_equal("[binary 11 bytes captured]", Preview.render(bytes, media_type: nil))
    assert_equal("[binary 11 bytes captured]",
                 Preview.render(bytes, media_type: MediaType.parse("image/png")),)
    assert_equal("[binary 11 bytes captured]",
                 Preview.render(bytes, media_type: MediaType.parse("application/octet-stream")),)
    assert_equal("[binary %d bytes captured]", Preview::BINARY_MARKER_FORMAT)
  end

  # Phase 3b's corrected recipe (P5-31): retag with the declared charset, then transcode with
  # both encodings named. §3.1's own one-step sentence returns "caf" plus replacement characters
  # for the same bytes and is on phase 10's inbound list.
  test "OBS-38: an ISO-8859-1 text body decodes through its declared charset" do
    latin1 = "caf\xE9 \xA0 \xFC".b
    rendered = Preview.render(latin1, media_type: MediaType.parse("text/plain; charset=iso-8859-1"))

    assert_equal("café   ü", rendered)
    assert_equal(::Encoding::UTF_8, rendered.encoding)
  end

  test "OBS-38: an absent or unrecognised charset falls back to UTF-8" do
    utf8 = "naïve – ✓".b

    assert_equal("naïve – ✓", Preview.render(utf8, media_type: MediaType.parse("text/plain")))
    assert_equal("naïve – ✓",
                 Preview.render(utf8, media_type: MediaType.parse("text/plain; charset=no-such")),)
  end

  test "OBS-38: truncated or malformed multibyte input yields replacement characters" do
    json = MediaType.parse("application/json; charset=utf-8")
    truncated = Preview.render("{\"k\":\"\xE4\xBD".b, media_type: json)

    assert_predicate(truncated, :valid_encoding?)
    assert_equal("{\"k\":\"�", truncated)
    malformed = Preview.render("\xFF\xFEok".b, media_type: json)

    assert_equal("��ok", malformed)
  end

  # P5-31: the discriminator. type "text", one of the structured subtypes, or an RFC 6839
  # +json/+xml suffix is text; everything else is binary, because rendering unknown bytes as
  # text is how a log line acquires a control character.
  test "OBS-38: text/*, the structured subtypes and the +json/+xml suffixes are text" do
    %w[text/html text/csv application/json application/xml application/yaml application/csv
       application/javascript application/graphql application/x-www-form-urlencoded
       application/x-ndjson application/problem+json application/atom+xml
       image/svg+xml].each do |type|
      assert_equal("ok", Preview.render("ok", media_type: MediaType.parse(type)), type)
    end
    %w[image/png application/octet-stream application/pdf audio/ogg application/jsonx
       application/x-json-stream].each do |type|
      assert_equal("[binary 2 bytes captured]",
                   Preview.render("ok", media_type: MediaType.parse(type)), type,)
    end
    assert_equal(::Set["json", "xml", "yaml", "csv", "javascript", "graphql",
                       "x-www-form-urlencoded", "x-ndjson",], Preview::TEXT_SUBTYPES,)
    assert_predicate(Preview::TEXT_SUBTYPES, :frozen?)
  end

  test "OBS-38: the input is never mutated and a non-BINARY String is read by its bytes" do
    bytes = "caf\xE9".b.freeze
    rendered = Preview.render(bytes, media_type: MediaType.parse("text/plain; charset=iso-8859-1"))

    assert_equal("café", rendered)
    assert_equal(::Encoding::BINARY, bytes.encoding)
    assert_equal("héllo", Preview.render("héllo", media_type: MediaType.parse("text/plain")))
  end

  test "OBS-38: a media type whose charset names an encoding Ruby lacks still renders" do
    duck = ::Struct.new(:type, :subtype, :charset).new("text", "plain", "no-such-encoding")

    assert_equal("caf�", Preview.render("caf\xE9".b, media_type: duck))
  end
end
