# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/serde_seam_assertions"
require "dexpace/serde/json"

# SERDE-3, SERDE-4, SERDE-9, SERDE-10, SERDE-12, SERDE-29 -- asserted THROUGH the lift target
# (SerdeSeamAssertions, phase 9's), in addition to codec_test.rb's and codec_load_test.rb's direct
# cases. This suite packages; it does not discover: every behaviour here was established by those
# two, so a failure is in the packaging and the assertion is wrong, not the codec. An extra suite
# beside codec_test.rb, the file's mirror.
class DexpaceSerdeJSONSeamConformanceTest < DexpaceTestCase
  include SerdeSeamAssertions

  test "the JSON codec satisfies the seam's adapter obligations" do
    codec = Dexpace::Serde::JSON.default

    assert_closes_nothing(codec)
    assert_buffer_profile(codec)
    assert_failure_model(codec, malformed: "{not json")
    assert_io_error_passthrough(codec)
    assert_shareable(codec)
  end

  # SERDE-3's "even when the codec's own auto-close feature is enabled": every option this
  # adapter accepts, and the assertions hold under each.
  test "the obligations hold under every accepted option" do
    [{ max_nesting: 4 }, { allow_nan: true }, { allow_duplicate_key: true }, { script_safe: true },
     { encoders: {} },].each do |options|
      codec = Dexpace::Serde::JSON.build(options)

      assert_closes_nothing(codec)
      assert_buffer_profile(codec)
      assert_io_error_passthrough(codec)
    end
  end

  test "the assertion module names no adapter, so phase 9 can lift it as it is" do
    source = File.read(File.expand_path("../../../support/serde_seam_assertions.rb", __dir__))

    refute_match(/Serde::JSON|::JSON\b|json/, source)
  end
end
