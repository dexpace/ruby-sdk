# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "dexpace/version"
require_relative "dexpace/error"
require_relative "dexpace/error/invalid_argument_error"
require_relative "dexpace/model"
require_relative "dexpace/builder"
require_relative "dexpace/http/header_syntax"
require_relative "dexpace/http/header_name"
require_relative "dexpace/http/headers"
require_relative "dexpace/http/headers/builder"
require_relative "dexpace/http/status"
require_relative "dexpace/http/method"
require_relative "dexpace/http/protocol"
require_relative "dexpace/http/media_type"
require_relative "dexpace/http/percent_encoding"
require_relative "dexpace/http/query"
require_relative "dexpace/http/query/builder"
require_relative "dexpace/http/url"
require_relative "dexpace/http/request_options"
require_relative "dexpace/http/request_options/builder"
require_relative "dexpace/http/request"
require_relative "dexpace/http/request/builder"
require_relative "dexpace/http/response"
require_relative "dexpace/http/response/builder"

# Phase 2: the seam layer, in dependency order (see the block below for why the order matters).
require_relative "dexpace/error/seam_error"
require_relative "dexpace/error/closed_error"
require_relative "dexpace/error/cancelled_error"
require_relative "dexpace/closeable"
require_relative "dexpace/hooks"
require_relative "dexpace/cancellation"
require_relative "dexpace/cancellation/source"
require_relative "dexpace/async/settlement"
require_relative "dexpace/async/completer"
require_relative "dexpace/async/future"
require_relative "dexpace/registry"
require_relative "dexpace/bridge/async_over"
require_relative "dexpace/bridge/sync_over"
require_relative "dexpace/transport"
require_relative "dexpace/async_transport"
require_relative "dexpace/serde/error"
require_relative "dexpace/serde/serialization_error"
require_relative "dexpace/serde/deserialization_error"
require_relative "dexpace/serde"
require_relative "dexpace/operation"

# The dexpace Ruby SDK: an HTTP-client toolkit, not an HTTP client.
#
# This file issues explicit `require_relative`s for the whole tree rather than using an
# autoloader. That is not stylistic: every Ruby autoloader worth using is a gem, and SEAM-1 bars
# core from depending on one (docs/knowledge/notes/module-organization.md). It also turns the
# require-graph audit into a text scan rather than a runtime trace. Adding a file under
# lib/dexpace/ means adding a line above -- in dependency order, not alphabetical: a builder file
# follows its model because the model's EMPTY-style constants are evaluated at require time.
#
# The public wire model is flat under this namespace (Dexpace::Request, Dexpace::Headers) while
# its files sit under lib/dexpace/http/; the directory organises files and is not a namespace
# segment (docs/knowledge/notes/module-organization.md, phase 1's P1-1). Two of the constants
# shadow a Ruby core name inside `module Dexpace`: Dexpace::Method (::Method) is the one this
# phase adds. Write `::Method` inside core when Ruby's is meant; outside core a consumer's
# top-level Method still resolves to Ruby's, even after `include Dexpace`, because Object's own
# constants win over an included module's.
module Dexpace
end
