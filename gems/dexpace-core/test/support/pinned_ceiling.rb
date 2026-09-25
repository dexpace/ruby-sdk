# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Pins the materialisation ceiling to its default for one block, at the OVERRIDE tier -- the one
# CFG-1 puts above the environment -- so a test asserting against IO::MAX_MATERIALIZED_BYTES
# means the default whatever the host exports. Phase 10's repair of four phase-3b and phase-4b
# tests that asserted the default while the code reads the live value per call (5a's P5-56):
# with MAX_MATERIALIZED_BYTES=4096 exported, all four failed. The slot is restored in `ensure`
# (testing/4ef070df).
module PinnedCeiling
  extend self

  def with_default_ceiling
    Dexpace.configure do |builder|
      builder.override(Dexpace::Configuration::Keys::MAX_MATERIALIZED_BYTES,
                       Dexpace::IO::MAX_MATERIALIZED_BYTES.to_s,)
    end
    yield
  ensure
    Dexpace.reset_config!
  end
end
