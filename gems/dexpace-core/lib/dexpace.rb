# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "dexpace/version"
# Phase 4b: the trail module precedes the error root that includes it (P4-12). The order is
# load-bearing -- error.rb writes `include Dexpace::Suppressible` -- and suppressible.rb requires
# nothing, so nothing can re-enter error.rb before its body has run.
require_relative "dexpace/suppressible"
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

# Phase 3a: the byte-streaming layer, in dependency order -- the two failure types, the namespace
# with its ceiling, the read vocabulary, the reader, the write vocabulary, then the three sinks.
require_relative "dexpace/error/stream_error"
require_relative "dexpace/error/end_of_stream_error"
require_relative "dexpace/io"
require_relative "dexpace/io/typed_reads"
require_relative "dexpace/io/buffered_source"
require_relative "dexpace/io/typed_writes"
require_relative "dexpace/io/buffer"
require_relative "dexpace/io/buffered_sink"
require_relative "dexpace/io/tee_sink"

# Phase 3b: the body layer, in dependency order -- the contract and its factory home first, then
# the variants each factory names, the response side, the two logging wrappers, and the lazy typed
# response last.
require_relative "dexpace/http/body"
require_relative "dexpace/http/body/bytes_body"
require_relative "dexpace/http/body/buffer_body"
require_relative "dexpace/http/body/file_body"
require_relative "dexpace/http/body/stream_body"
require_relative "dexpace/http/body/chunked_body"
require_relative "dexpace/http/body/form_body"
require_relative "dexpace/http/body/multipart_body"
require_relative "dexpace/http/body/response_body"
require_relative "dexpace/http/body/request_logging_body"
require_relative "dexpace/http/body/response_logging_body"
require_relative "dexpace/http/typed_response"

# Phase 4a: the execution context, in dependency order -- the conflict error, the module the
# three flavours share, the private bounded map and the store over it, the instrumentation
# subsystem (the flavour table, the two no-op singletons, the bundle that carries them), then the
# private key generator and the three flavours innermost first, since each promotion names its
# successor.
require_relative "dexpace/error/context_conflict_error"
require_relative "dexpace/context"
require_relative "dexpace/bounded_map"
require_relative "dexpace/context_store"
require_relative "dexpace/instrumentation/trace_id_flavour"
require_relative "dexpace/instrumentation/no_span"
require_relative "dexpace/instrumentation/no_tracer"
require_relative "dexpace/instrumentation/bundle"
require_relative "dexpace/context/call_key"
require_relative "dexpace/context/exchange_context"
require_relative "dexpace/context/request_context"
require_relative "dexpace/context/dispatch_context"

# Phase 4b: the recovery layer, in dependency order -- the cause walk, the two flat errors, the
# closed outcome and its two variants, the Recovery namespace with its buffering function, the
# transform contract, the three transforms, the request chain, the private ownership helper, the
# response chain and the orchestrator. The trail module sits at the top of this file, before the
# error root that includes it.
require_relative "dexpace/each_cause"
require_relative "dexpace/error/outcome_error"
require_relative "dexpace/error/protocol_error"
require_relative "dexpace/outcome"
require_relative "dexpace/outcome/success"
require_relative "dexpace/outcome/failure"
require_relative "dexpace/recovery"
require_relative "dexpace/recovery/transform"
require_relative "dexpace/recovery/idempotency_key_step"
require_relative "dexpace/recovery/client_identity_step"
require_relative "dexpace/recovery/error_mapping_step"
require_relative "dexpace/recovery/request_chain"
require_relative "dexpace/recovery/ownership"
require_relative "dexpace/recovery/response_chain"
require_relative "dexpace/recovery/orchestrator"

# Phase 4c: the stage pipeline, in dependency order -- the one error class, then pipeline.rb FIRST
# among the nested set (every file under pipeline/ reopens `class Pipeline`, and the class's own
# definition must be the one that creates it), then stage before stages (Stages names Stage at
# load), the step protocol, the entry, the cursor and its two private drivers, the builder (which
# names Entry at load), the transform adapter, and the async runtime last.
require_relative "dexpace/error/pipeline_error"
require_relative "dexpace/pipeline"
require_relative "dexpace/pipeline/stage"
require_relative "dexpace/pipeline/stages"
require_relative "dexpace/pipeline/step"
require_relative "dexpace/pipeline/entry"
require_relative "dexpace/pipeline/cursor"
require_relative "dexpace/pipeline/sync_driver"
require_relative "dexpace/pipeline/async_driver"
require_relative "dexpace/pipeline/builder"
require_relative "dexpace/pipeline/transform_step"
require_relative "dexpace/async_pipeline"

# Phase 5a: configuration and the clock, in dependency order -- the five free-standing utilities
# first (the build descriptor, the UUID generator, the retryability classifier, the HTTP-date
# codec and the private deep-value helper), then the clock, the async delay over it, the
# configuration chain (configuration.rb owns the load order of its keys, sources, private
# parsers and builder, which reopen the class it declares and never appear here), the
# process-wide slot over the chain, and the proxy model last (proxy.rb likewise owns
# proxy/type, proxy/host_pattern and the private resolver). Ten lines for seventeen files.
# `time` is required by http_date.rb and `uri` by proxy/resolution.rb, each in the file that
# uses it; the allowlist does not grow (R5).
require_relative "dexpace/build_info"
require_relative "dexpace/uuid"
require_relative "dexpace/retryability"
require_relative "dexpace/http_date"
require_relative "dexpace/clock"
require_relative "dexpace/async/delay"
require_relative "dexpace/deep_value"
require_relative "dexpace/configuration"
require_relative "dexpace/config"
require_relative "dexpace/proxy"

# Phase 5c: tracing and metrics, in dependency order -- phase 5b's diagnostics module first (its
# three constants shipped early by 5c, P5-71: scope.rb and tracing.rb read the two key names),
# then the scope handle, the tracing module over it, the metrics SPI, the HTTP-tracer vocabulary
# and the bus adapter over it. The four phase-4a files above gained their protocols in place.
require_relative "dexpace/instrumentation/diagnostics"

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
