# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# The first of the three probe families every pipeline suite is written against (with
# ForkingProbe and StateProbe, one class per file): steps that record what the runtime did to
# them and drive nothing but the cursor they were handed. None declares #stage (R10 row 5: the
# stage travels as the install-time argument), none acquires a resource inside a block it yields
# from, and none is public API -- they live in dexpace-core's test tree for the reason
# fake_transport.rb states.
#
# A Data value object, deliberately (verified fact 3): two instances with equal members are == and
# not equal?, which is the only pair that discriminates PIPE-6's reference-identity rule from a
# value-equality implementation. The `log` member is what decides ==, so the PIPE-6 pair is built
# over ONE shared log Array and stays == across execution; two probes over separate logs stop
# being == the moment either runs. A two-member Data has no one-argument constructor: every
# construction is ProbeStep.new(tag:, log:).
class ProbeStep < Data.define(:tag, :log)
  def call(request, cursor)
    log << [:enter, tag]
    begin
      cursor.call(request)
    ensure
      log << [:exit, tag]
    end
  end
end
