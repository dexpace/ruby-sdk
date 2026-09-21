# frozen_string_literal: true
# SPDX-License-Identifier: MIT

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# The workspace's shared test base. This reaches out of the gem directory into the repository's
# own test support, which is not the cross-gem require_relative styleguide 12.6 forbids -- that
# rule is about reaching into another *gem's* internals.
require_relative "../../../test/support/dexpace_test_case"
# The one connection that parks net-http's Timeout thread outside every test's thread count on
# the rows whose net-http still connects through Timeout.timeout (see the file).
require_relative "../../../test/support/net_http_warmup"
