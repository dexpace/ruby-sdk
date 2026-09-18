# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "test_helper"

# NFR-15: the version a published artifact reports at runtime is the real one. Styleguide 12.7:
# no constant outside Dexpace::.
class DexpaceTest < DexpaceTestCase
  # The top-level namespace is snapshotted around the require, so "defines nothing outside
  # Dexpace" holds whether this file loads alone or after the other five gems in one
  # `rake test:gems` process, where Dexpace already exists. The five stdlib features core
  # requires (all on the require allowlist) are loaded first: the constants they define --
  # URI, StringScanner and strscan's ScanError alias, phase 3b's SecureRandom, phase 5a's
  # `time`, which pulls in Date and DateTime for Time#httpdate, and phase 6c's Digest -- are
  # theirs, not the entry file's.
  require "uri"
  require "strscan"
  require "securerandom"
  require "time"
  require "digest"
  TOP_LEVEL_BEFORE = Object.constants
  NAMESPACE_BEFORE = defined?(Dexpace) ? Dexpace.constants(false) : []
  require "dexpace"
  TOP_LEVEL_ADDED = (Object.constants - TOP_LEVEL_BEFORE).freeze
  NAMESPACE_ADDED = (Dexpace.constants(false) - NAMESPACE_BEFORE).freeze

  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    gemspec = File.expand_path("../dexpace-core.gemspec", __dir__)
    spec = Gem::Specification.load(gemspec)

    assert_equal(spec.version.to_s, Dexpace::VERSION)
  end

  # Every public constant the surface manifest records, and the check that catches a file added
  # to lib/ and forgotten in the entry point. Phase 1's domain model, then phase 2's seam layer,
  # then phase 3a's byte-streaming layer, then phase 3b's body layer, then phase 4a's execution
  # context, phase 4b's recovery layer, phase 4c's pipeline, phase 5a's configuration layer and
  # phase 6a's retry layer (the flat RetryPredicateError beside the Resilience namespace);
  # Dexpace::Hooks, Dexpace::BoundedMap, Dexpace::CallKey, Dexpace::Recovery::Ownership, the two
  # pipeline drivers, Dexpace::ConfigParsers, Dexpace::DeepValue, Dexpace::ProxyResolution and
  # 6a's Resilience::PacingParsers and Resilience::RetryStepHelpers are private_constants and
  # appear in no constants(false) list. Phase 5c's tracing and metrics layer and phase 5b's
  # logging layer add no flat constant: everything either ships is under
  # Dexpace::Instrumentation, which the Layers case below pins. Phase 6c adds two flat names,
  # its namespace and AUTH-6's general resolution error.
  DOMAIN_MODEL = %i[
    Error InvalidArgumentError Model Builder HeaderSyntax HeaderName Headers Status Method
    Protocol MediaType PercentEncoding Query URL RequestOptions Request Response
  ].freeze
  SEAM_LAYER = %i[
    SeamError ClosedError CancelledError Closeable Cancellation Async Registry Bridge Transport
    AsyncTransport Serde Operation
  ].freeze
  IO_LAYER = %i[StreamError EndOfStreamError IO].freeze
  BODY_LAYER = %i[
    Body BytesBody BufferBody StreamBody ChunkedBody FormBody FileBody MultipartBody ResponseBody
    RequestLoggingBody ResponseLoggingBody TypedResponse
  ].freeze
  CONTEXT_LAYER = %i[
    ContextConflictError Context ContextStore Instrumentation DispatchContext RequestContext
    ExchangeContext
  ].freeze
  RECOVERY_LAYER = %i[Suppressible OutcomeError ProtocolError Outcome Recovery].freeze
  PIPELINE_LAYER = %i[PipelineError Pipeline AsyncPipeline].freeze
  CONFIGURATION_LAYER = %i[
    BuildInfo UUID Retryability HTTPDate Clock Configuration Proxy
  ].freeze
  RESILIENCE_LAYER = %i[RetryPredicateError Resilience].freeze
  # Phase 6c: the namespace and the one flat error AUTH-6 scopes generally; everything else the
  # layer ships is under Dexpace::Auth, which the Layers case below pins.
  AUTH_LAYER = %i[Auth AuthResolutionError].freeze
  LAYERS = [
    DOMAIN_MODEL, SEAM_LAYER, IO_LAYER, BODY_LAYER, CONTEXT_LAYER, RECOVERY_LAYER, PIPELINE_LAYER,
    CONFIGURATION_LAYER, RESILIENCE_LAYER, AUTH_LAYER,
  ].flatten.freeze

  test "defines nothing outside the Dexpace namespace" do
    assert_empty(TOP_LEVEL_ADDED - [:Dexpace], "top-level constants added by the entry file")
    assert_empty(NAMESPACE_ADDED - [:VERSION, *LAYERS], "constants added under Dexpace")
    assert_includes(Dexpace.constants(false), :VERSION)
  end

  # A consumer requires "dexpace" and nothing else.
  test "requiring dexpace alone makes the whole domain model resolve" do
    assert_equal(Dexpace::Request, Dexpace.const_get(:Request))
    assert_equal(Dexpace::Headers, Dexpace.const_get(:Headers))
    assert_equal(Dexpace::Status, Dexpace.const_get(:Status))
    assert_equal(200, Dexpace::Status::OK.code)
  end

  test "every constant the manifest records is reachable from Dexpace" do
    LAYERS.each { |name| assert(Dexpace.const_defined?(name, false), "#{name} missing") }
    assert_empty(LAYERS - Dexpace.constants(false))
    %i[Headers Query RequestOptions Request Response MultipartBody].each do |name|
      assert(Dexpace.const_get(name).const_defined?(:Builder, false), "#{name}::Builder")
    end
  end

  # A consumer requires "dexpace" and nothing else, and every layer resolves -- one case per phase,
  # in a nested class because the smoke suite outgrew Metrics/ClassLength once the three phase-4
  # lanes landed their pins beside one another (the split every larger suite in this gem uses).
  class Layers < DexpaceTestCase
    # A consumer requires "dexpace" and nothing else: the body layer resolves too (phase 3b), and
    # the two constants that are nested rather than flat sit where HTTP-3 and R6 put them.
    test "requiring dexpace alone makes the whole body layer resolve" do
      assert_equal(Dexpace::Body, Dexpace.const_get(:Body))
      assert_equal(Dexpace::TypedResponse, Dexpace.const_get(:TypedResponse))
      assert_equal(Dexpace::MultipartBody::Part, Dexpace::MultipartBody.const_get(:Part))
      assert_equal(1024 * 1024, Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES)
      refute(Dexpace::Body.const_defined?(:Part, false), "Dexpace::Body::Part is not a namespace")
    end

    # A consumer requires "dexpace" and nothing else: the recovery layer resolves too (phase 4b),
    # the trail module precedes the error root that includes it, and Ownership is private.
    test "requiring dexpace alone makes the whole recovery layer resolve" do
      assert_operator(Dexpace::Error, :<, Dexpace::Suppressible)
      assert_equal(Dexpace::Outcome::Failure, Dexpace::Outcome.const_get(:Failure))
      assert_equal(Dexpace::Recovery::Orchestrator, Dexpace::Recovery.const_get(:Orchestrator))
      refute_includes(Dexpace::Recovery.constants(false), :Ownership, "a private_constant")
      assert_raises(::NameError) { Dexpace::Recovery::Ownership }
    end

    # A consumer requires "dexpace" and nothing else: the pipeline resolves too (phase 4c), the
    # runtime's nested vocabulary with it, and the two drivers are private.
    test "requiring dexpace alone makes the whole pipeline resolve, its two drivers private" do
      assert_equal(16, Dexpace::Pipeline.const_get(:Stages)::ALL.size)
      assert_empty(Dexpace::Pipeline.constants(false) & %i[SyncDriver AsyncDriver], "private")
      assert_raises(::NameError) { Dexpace::Pipeline::SyncDriver }
    end

    # A consumer requires "dexpace" and nothing else: the tracing and metrics layer (phase 5c)
    # and the logging facade (phase 5b) resolve too, the whole of both under
    # Dexpace::Instrumentation -- twenty-six public constants -- and everything private stays
    # private: the six no-op classes, the two instrument singletons and the current-span key
    # (5c's), and the null sink's class, the inert event's class, the collision latch, the
    # reserved-key table, the renderer and the emitter (5b's).
    test "requiring dexpace alone makes the whole tracing, metrics and logging layer resolve" do
      instrumentation = Dexpace::Instrumentation

      assert_equal(
        %i[
          AsyncStep Bundle CallableAdapter Diagnostics Event Events HTTPLogging HTTPTracer Keys
          Logger NO_METER NO_SCOPE NO_SPAN NO_TRACER NO_TRACER_FACTORY NULL NULL_SINK Preview
          RedactionPolicy Redactor Scope Severity Step TraceIdFlavour Tracing
        ],
        instrumentation.constants(false).sort,
      )
      assert_equal(%i[trace.id span.id], instrumentation::Diagnostics::DEFAULT_KEYS)
      assert_same(instrumentation::Event::INERT, instrumentation::Logger::NULL.event(:error))
      assert_raises(::NameError) { Dexpace::Instrumentation::NoScope }
      assert_raises(::NameError) { Dexpace::Instrumentation::NO_COUNTER }
      assert_raises(::NameError) { Dexpace::Instrumentation::CURRENT_SPAN_KEY }
      assert_raises(::NameError) { Dexpace::Instrumentation::NullSink }
      assert_raises(::NameError) { Dexpace::Instrumentation::CollisionLatch }
      assert_raises(::NameError) { Dexpace::Instrumentation::ReservedKeys }
      assert_raises(::NameError) { Dexpace::Instrumentation::Render }
      assert_raises(::NameError) { Dexpace::Instrumentation::Emitter }
      assert_raises(::NameError) { Dexpace::Instrumentation::Event::Inert }
      assert_raises(::NameError) { Dexpace::Instrumentation::AsyncStep::Pending }
    end

    # A consumer requires "dexpace" and nothing else: the authentication layer resolves too
    # (phase 6c), under Dexpace::Auth, its one private_constant and its parser's private class as
    # unreachable as Dexpace::Hooks.
    test "requiring dexpace alone makes the whole authentication layer resolve" do
      auth = Dexpace::Auth

      assert_equal(
        %i[
          AsyncBearerStamper AsyncStep BasicHandler BearerProvider BearerStamper BearerToken
          Challenge ChallengeHandlerChain Challenges Descriptor DigestHandler HTTPSRequiredError
          KeyCredential KeyStamper NamedKeyCredential PasswordCredential ProviderError REDACTED
          Requirement Resolver Scheme Step UnencodableCredentialError
        ],
        auth.constants(false).sort,
      )
      assert_equal(Dexpace::AuthResolutionError, Dexpace.const_get(:AuthResolutionError))
      assert_same(Dexpace::Pipeline::Stages::AUTH, auth::Step.build(stamper: auth::Step::NO_STAMP).stage)
      assert_raises(::NameError) { Dexpace::Auth::Validation }
      assert_raises(::NameError) { Dexpace::Auth::Challenges::Parser }
      assert_raises(::NameError) { Dexpace::Auth::DigestHandler::HASHES }
      assert_raises(::NameError) { Dexpace::Auth::AsyncStep::Exchange }
    end

    # A consumer requires "dexpace" and nothing else: the execution context resolves too (phase
    # 4a), the instrumentation subsystem keeps its namespace (design §8.1), and the two private
    # constants are as unreachable as Dexpace::Hooks.
    test "requiring dexpace alone makes the whole execution context resolve" do
      assert_equal(Dexpace::ContextStore, Dexpace.const_get(:ContextStore))
      assert_equal(Dexpace::DispatchContext, Dexpace.const_get(:DispatchContext))
      assert_equal(Dexpace::Instrumentation::Bundle, Dexpace::Instrumentation.const_get(:Bundle))
      assert_equal(1024, Dexpace::ContextStore::MAX_TRACKED_CONTEXTS)
      refute_includes(Dexpace.constants(false), :BoundedMap, "Dexpace::BoundedMap is private")
      refute_includes(Dexpace.constants(false), :CallKey, "Dexpace::CallKey is private")
      assert_raises(::NameError) { Dexpace::BoundedMap }
      assert_raises(::NameError) { Dexpace::CallKey }
    end

    # A consumer requires "dexpace" and nothing else: the retry layer resolves too (phase 6a) --
    # the five public Resilience constants, the flat error, and the two private helpers and the
    # two private per-call classes as unreachable as Dexpace::Hooks. Phase 6b and 6c add their
    # own constants under Resilience beside these.
    test "requiring dexpace alone makes the whole retry layer resolve, its helpers private" do
      resilience = Dexpace::Resilience

      assert_equal(%i[AsyncRetryStep Policy RecoveryRetry Resend RetrySettings RetryStep],
                   resilience.constants(false).sort,)
      assert_equal(Dexpace::RetryPredicateError, Dexpace.const_get(:RetryPredicateError))
      assert_equal(2, resilience::Policy::DEFAULT_MAX_RETRIES)
      assert_raises(::NameError) { Dexpace::Resilience::PacingParsers }
      assert_raises(::NameError) { Dexpace::Resilience::RetryStepHelpers }
      assert_raises(::NameError) { Dexpace::Resilience::AsyncRetryStep::Pump }
      assert_raises(::NameError) { Dexpace::Resilience::RetryStep::Run }
      assert_raises(::NameError) { Dexpace::Resilience::RecoveryRetry::Run }
      assert_raises(::NameError) { Dexpace::Resilience::RetrySettings::UNSET }
    end

    # A consumer requires "dexpace" and nothing else: the seam layer resolves too (phase 2).
    test "requiring dexpace alone makes the whole seam layer resolve" do
      assert_equal(Dexpace::Transport, Dexpace.const_get(:Transport))
      assert_equal(Dexpace::AsyncTransport, Dexpace.const_get(:AsyncTransport))
      assert_equal(Dexpace::Serde, Dexpace.const_get(:Serde))
      assert_equal(Dexpace::Operation, Dexpace.const_get(:Operation))
      assert_equal(Dexpace::Registry, Dexpace.const_get(:Registry))
      assert_equal(Dexpace::Cancellation, Dexpace.const_get(:Cancellation))
      assert_equal(Dexpace::Async::Future, Dexpace::Async.const_get(:Future))
      assert_equal(Dexpace::Closeable, Dexpace.const_get(:Closeable))
      refute_includes(Dexpace.constants(false), :Hooks, "Dexpace::Hooks is a private_constant")
      assert_raises(::NameError) { Dexpace::Hooks }
    end

    # A consumer requires "dexpace" and nothing else: the byte-streaming layer resolves too
    # (phase 3a).
    test "requiring dexpace alone makes the whole streaming layer resolve" do
      assert_equal(Dexpace::IO::Buffer, Dexpace::IO.const_get(:Buffer))
      assert_equal(Dexpace::IO::BufferedSource, Dexpace::IO.const_get(:BufferedSource))
      assert_equal(Dexpace::IO::BufferedSink, Dexpace::IO.const_get(:BufferedSink))
      assert_equal(Dexpace::IO::TeeSink, Dexpace::IO.const_get(:TeeSink))
      assert_equal(Dexpace::StreamError, Dexpace.const_get(:StreamError))
      assert_equal(Dexpace::EndOfStreamError, Dexpace.const_get(:EndOfStreamError))
    end
  end

  # The shadowing names this SDK never defines: each would make a bare `rescue ArgumentError`,
  # `rescue IOError` or `rescue EOFError` inside `module Dexpace` stop catching Ruby's own
  # (deviation P1-3; phase 3a's design for the two I/O names).
  test "never defines Dexpace::ArgumentError, Dexpace::IOError or Dexpace::EOFError" do
    refute_includes(Dexpace.constants(false), :ArgumentError)
    refute_includes(Dexpace.constants(false), :IOError)
    refute_includes(Dexpace.constants(false), :EOFError)
  end

  # Dexpace::Method shadows ::Method only inside core (the entry file's YARD block says so);
  # a consumer's top-level Method is still Ruby's, even after `include Dexpace`.
  test "Dexpace::Method does not shadow Ruby's Method for a consumer" do
    consumer = Class.new { include Dexpace }

    assert_equal(::Method, consumer.class_eval { Method })
    assert_instance_of(::Method, consumer.new.method(:to_s))
  end
end
