# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a gemspec that raises while it evaluates -- the shape of a helper that cannot
# find its VERSIONS entry. Gem::Specification.load rescues the error, warns and returns nil,
# and the audit must name this file rather than dereference nil.
raise "VERSIONS has no entry for dexpace-core"
