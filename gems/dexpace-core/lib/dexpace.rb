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
require_relative "dexpace/instrumentation/scope"
require_relative "dexpace/instrumentation/tracing"
require_relative "dexpace/instrumentation/meter"
require_relative "dexpace/instrumentation/http_tracer"
require_relative "dexpace/instrumentation/callable_adapter"

# Phase 5b: the logging facade and redaction, in dependency order -- the severity set, the two
# vocabularies, the default sink, the private renderer, the redaction policy and the redactor
# (diagnostics.rb, which the event folds through, is 5c's line above), the event and the facade
# over it, the two containment functions, the preview renderer, the level set, then the private
# emitter and the two steps. Four earlier files pull the front of this tree in ahead of here --
# closeable.rb and hooks.rb (phase 2) and proxy/resolution.rb (phase 5a) require the logger and
# the containment for their diagnostics -- and that is not a cycle: nothing in this tree
# requires closeable, hooks or the proxy, and require_relative is idempotent, so these lines are
# the declaration of the order and not always the first load. `uri` is required by redactor.rb
# in the file that uses it; the allowlist does not grow.
require_relative "dexpace/instrumentation/severity"
require_relative "dexpace/instrumentation/keys"
require_relative "dexpace/instrumentation/null_sink"
require_relative "dexpace/instrumentation/render"
require_relative "dexpace/instrumentation/redaction_policy"
require_relative "dexpace/instrumentation/redactor"
require_relative "dexpace/instrumentation/event"
require_relative "dexpace/instrumentation/logger"
require_relative "dexpace/instrumentation/contain"
require_relative "dexpace/instrumentation/preview"
require_relative "dexpace/instrumentation/http_logging"
require_relative "dexpace/instrumentation/emitter"
require_relative "dexpace/instrumentation/step"
require_relative "dexpace/instrumentation/async_step"

# Phase 6a: the retry layer, in dependency order -- after 5b's block, because the settings read
# the clock and the configuration slot (5a) and the steps emit through the logging facade (5b)
# and the HTTP-tracer vocabulary (5c). The one flat error first, then the shared policy core
# (the private parsers, the policy over them, the re-sendability gate, the settings), then the
# private helpers the two stage drivers share, the two drivers, and the recovery-stack engine.
# Three earlier files gained a method or a keyword in place and appear above: http_date.rb (the
# day group), error/protocol_error.rb (the baked flag) and pipeline/cursor.rb with the two
# runtimes and the two instrumentation steps (the context-bundle widening).
require_relative "dexpace/error/retry_predicate_error"
require_relative "dexpace/resilience/pacing_parsers"
require_relative "dexpace/resilience/policy"
require_relative "dexpace/resilience/resend"
require_relative "dexpace/resilience/retry_settings"
require_relative "dexpace/resilience/retry_step_helpers"
require_relative "dexpace/resilience/retry_step"
require_relative "dexpace/resilience/async_retry_step"
require_relative "dexpace/resilience/recovery_retry"

# Phase 6c: the authentication layer, in dependency order -- the namespace and the flat
# resolution error, the private non-blank helper, the closed scheme set, the requirement and
# the descriptor over it, the resolver, the four credential types, the challenge and its
# parser, the two challenge handlers and the chain over them, the key stamper, the bearer
# provider function, the three namespaced errors (filed under auth/, where their constants
# live), the two bearer stampers, then the two pillar steps, the async one over the sync one.
# bounded_map.rb, which the Digest handler's nonce store reaches by a bare name, is phase 4a's
# line above and gains #update in place. `digest` and `securerandom` are required by
# digest_handler.rb and `strscan` by challenges.rb, each in the file that uses it; all three
# were on the allowlist before this phase.
require_relative "dexpace/auth"
require_relative "dexpace/error/auth_resolution_error"
require_relative "dexpace/auth/validation"
require_relative "dexpace/auth/scheme"
require_relative "dexpace/auth/requirement"
require_relative "dexpace/auth/descriptor"
require_relative "dexpace/auth/resolver"
require_relative "dexpace/auth/bearer_token"
require_relative "dexpace/auth/key_credential"
require_relative "dexpace/auth/named_key_credential"
require_relative "dexpace/auth/password_credential"
require_relative "dexpace/auth/challenge"
require_relative "dexpace/auth/challenges"
require_relative "dexpace/auth/basic_handler"
require_relative "dexpace/auth/unencodable_credential_error"
require_relative "dexpace/auth/digest_handler"
require_relative "dexpace/auth/challenge_handler_chain"
require_relative "dexpace/auth/key_stamper"
require_relative "dexpace/auth/provider_error"
require_relative "dexpace/auth/bearer_provider"
require_relative "dexpace/auth/bearer_stamper"
require_relative "dexpace/auth/async_bearer_stamper"
require_relative "dexpace/auth/https_required_error"
require_relative "dexpace/auth/step"
require_relative "dexpace/auth/async_step"

# Phase 6b: the redirect layer, in dependency order -- after 6a's and 6c's blocks, because the
# step consults 6a's Resend (widened in place above with REDIR-6's predicate), 5b's logger and
# 4c's stages. The flat NotReplayableError first (filed under error/ beside RetryPredicateError,
# 6a's P6-56 precedent), then the two private resolution helpers, the public snapshot, the event
# and key vocabularies, the namespaced error, the three private per-call helpers -- the chain,
# the emitter and the re-issue builder -- and the pillar step last. `uri` is required by
# location.rb and step.rb, the files that name it; it was on the allowlist before phase 1.
require_relative "dexpace/error/not_replayable_error"
require_relative "dexpace/redirect/origin"
require_relative "dexpace/redirect/location"
require_relative "dexpace/redirect/condition_snapshot"
require_relative "dexpace/redirect/events"
require_relative "dexpace/redirect/scheme_downgrade_error"
require_relative "dexpace/redirect/chain"
require_relative "dexpace/redirect/emitter"
require_relative "dexpace/redirect/reissue"
require_relative "dexpace/redirect/step"

# Phase 7b: the Server-Sent Events layer, in dependency order. Nothing here depends on phases
# 4c through 6: the namespace file needs only the sentinel type it holds the two instances of;
# the two errors need the error root; the line machine reads a byte source through #getbyte
# (3a's BufferedSource satisfies its interface structurally, and it is deliberately NOT built on
# #read_line_utf8, whose IO-14 grammar keeps a lone CR as content where SSE-2 terminates on it);
# the event value is a Data including Model; the reader sits on the line machine and the value;
# the facade includes phase 2's Closeable, reads a phase-3b response body's source, and requires
# the typed adapter itself; the typed adapter names the two sentinels. The layer requires no
# stdlib feature at all and names no Dexpace::Serde constant, which `gates:serde_boundary` scans
# for (SSE-37).
require_relative "dexpace/sse"
require_relative "dexpace/sse/sentinel"
require_relative "dexpace/sse/limit_exceeded_error"
require_relative "dexpace/sse/stream_state_error"
require_relative "dexpace/sse/line_reader"
require_relative "dexpace/sse/event"
require_relative "dexpace/sse/reader"
require_relative "dexpace/sse/stream"
require_relative "dexpace/sse/typed_stream"

# Phase 7c: the pagination layer, in dependency order -- after 6b's block, though it needs only
# phase 2's closeable.rb, phase 1's model and the async pivot. The page value first, because it is
# also the namespace every later file reopens; then the strategy vocabulary (the info value, the
# query splice, the private link-header grammar, the three built-in strategies), the private
# lifetime owner and the private close disciplines both views share, the two views, the two
# engines, and the fetcher front-end last. `uri` is required by url.rb, which page.rb requires; it
# was on the allowlist before phase 1, and nothing under page/ names a serializer.
require_relative "dexpace/page"
require_relative "dexpace/page/page_state_error"
require_relative "dexpace/page/info"
require_relative "dexpace/page/query_rewriter"
require_relative "dexpace/page/link_header"
require_relative "dexpace/page/cursor_strategy"
require_relative "dexpace/page/page_number_strategy"
require_relative "dexpace/page/link_strategy"
require_relative "dexpace/page/walk"
require_relative "dexpace/page/closing"
require_relative "dexpace/page/items"
require_relative "dexpace/page/pages"
require_relative "dexpace/page/paginator"
require_relative "dexpace/page/async_paginator"
require_relative "dexpace/page/fetchers"

# Phase 7a: the serialization layer, in dependency order -- after 6b's block, because the two
# handlers read 3b's Response and Body and 4b's Recovery and ProtocolError, and the whole layer
# raises through phase 2's Serde::DeserializationError. The decode context first (every witness
# raises through it), the witness predicates (every combinator is validated by them), the encode
# walk and its OMIT sentinel (Tristate's #dexpace_dump returns it), the scalar-witness table, the
# tri-state type with its combinator, the three container combinators, the ISO-8601 witness, and
# the two response handlers last. No namespace file: Dexpace::Serde is phase 2's serde.rb, which
# witness.rb reopens. `time` is required by instant.rb, the file that names it; it has been on
# the allowlist since phase 5a.
require_relative "dexpace/serde/decode_context"
require_relative "dexpace/serde/witness"
require_relative "dexpace/serde/native"
require_relative "dexpace/serde/scalars"
require_relative "dexpace/serde/tristate"
require_relative "dexpace/serde/list"
require_relative "dexpace/serde/map"
require_relative "dexpace/serde/nullable"
require_relative "dexpace/serde/instant"
require_relative "dexpace/serde/decoding_handler"
require_relative "dexpace/serde/status_aware_handler"

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
