# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "dexpace/version"

# The dexpace Ruby SDK: an HTTP-client toolkit, not an HTTP client.
#
# This file issues explicit `require_relative`s for the whole tree rather than using an
# autoloader. That is not stylistic: every Ruby autoloader worth using is a gem, and SEAM-1 bars
# core from depending on one (docs/knowledge/notes/module-organization.md). It also turns the
# require-graph audit into a text scan rather than a runtime trace. Adding a file under
# lib/dexpace/ means adding a line above.
module Dexpace
end
