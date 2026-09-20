# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# Exercises: SSE-19 (the documented divergence its MAY charges for), SSE-11 (documented as NOT the
# line cap), IO-9/IO-14 (phase 3a's line-cap finding, whose closure is a sentence in this
# subsystem's source and a sentence in phase 3a's). SSE-19 charges taking its MAY with
# "documenting the divergence", and the finding's third obligation is that the relationship
# between phase 3a's ceiling and 7b's cap be visible from the code and not only from a document.
# A doc-comment test is unusual; it is written because both obligations are discharged by prose,
# and prose is exactly what silently disappears in a later refactor. No lib/ mirror.
class DexpaceSSEDocumentationTest < DexpaceTestCase
  SOURCE = ::File.read(::File.expand_path("../../../lib/dexpace/sse.rb", __dir__))
  TYPED_READS = ::File.read(::File.expand_path("../../../lib/dexpace/io/typed_reads.rb", __dir__))

  test "SSE-19: MAX_LINE_BYTES's YARD names the requirement and the divergence" do
    assert_match(/SSE-19/, SOURCE)
    assert_match(/documented divergence|documenting the divergence/, SOURCE)
    assert_match(/REJECTS|rejected/, SOURCE)
    assert_match(/never truncates/, SOURCE)
  end

  test "the line cap: MAX_LINE_BYTES's YARD names phase 3a's ceiling and the layer split" do
    assert_match(/MAX_MATERIALIZED_BYTES/, SOURCE)
    assert_match(/different bound at a different layer|not a second ceiling/, SOURCE)
    assert_match(/line-cap finding/, SOURCE)
    assert_match(/#read_line_utf8/, SOURCE)
  end

  test "the two caps are documented as chosen rather than derived" do
    assert_match(/chosen, not derived|chosen rather than derived/i, SOURCE)
  end

  test "SSE-11's cap is documented as NOT the line cap" do
    assert_match(/not the line cap/i, SOURCE)
    assert_match(/2\^31 - 1|2_147_483_647/, SOURCE)
  end

  test "phase 3a's #read_line_utf8 YARD no longer names SSE-11 or 7b as its caller" do
    # The finding's premise was false and its ID was wrong (the design's R4); the sentence that
    # carried both sat on the method itself. Both corrections landed in the same change as the
    # cap, and this pins them.
    yard = TYPED_READS[/(?:^\s*#.*\n)+\s*def read_line_utf8/]

    refute_nil(yard)
    refute_match(/cap SSE-11 requires|SSE-11 obliges|SSE machine, whose/, yard)
    assert_match(/not SSE-11, which caps the retry field/, yard)
    assert_match(/SSE-19/, yard)
    assert_match(/MAX_LINE_BYTES/, yard)
    assert_match(/has no\s+#?\s*caller in this repository/, yard)
  end
end
