# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "json"
require "date"
require "time"
require "dexpace"

module Dexpace
  module Serde
    module JSON
      # The seam's six methods over one private ::JSON::Coder (SEAM-19–SEAM-21, SERDE-1–SERDE-4,
      # SERDE-9–SERDE-12, SERDE-25, SERDE-26, SERDE-29). A plain class, not a Data: it holds an
      # engine that is an implementation detail with no value semantics. Frozen at the end of
      # `#initialize`, `.new` private, `.build` the one constructor and `.default` a FRESH instance
      # per call (SERDE-25).
      #
      # SERDE-26 is satisfied literally rather than through §11.18's fallback clause (P7-4): the
      # constructor takes OPTIONS, never a caller's coder, so "built around a caller-supplied codec
      # instance" never happens, and each instance owns a private ::JSON::Coder built from its own
      # options -- json 2.19.9's per-instance, freezable, thread-safe engine (verified), which is
      # also what makes one frozen codec safe to share across workers with no per-type cache to
      # publish (SERDE-29): the witness is supplied per call and nothing is memoised by type.
      #
      # The options are validated against a frozen allowlist -- `max_nesting`, `allow_nan`,
      # `allow_duplicate_key`, `script_safe` and `encoders` -- and an unknown key is the SDK's own
      # InvalidArgumentError, because the library's own behaviour differs across the supported
      # range: json 2.19.9 SWALLOWS an unknown Coder option (a forwarded typo silently configures a
      # different codec) and json 3.0 refuses it with a keyword error. Two options are set by this
      # class and not by the caller: `strict: true` always, belt and braces beside core's Native
      # walk, which refuses every non-native value before the generator sees it -- verified fact 3
      # is that ::JSON.generate otherwise stringifies an Object silently; and
      # `allow_duplicate_key: false` unless the caller opts in, because a duplicate key is
      # accepted-last-wins on json 2.9, a WARNING on 2.19.9 and a ParserError on 3.0, and the
      # explicit option makes it one DeserializationError across the range. `encoders:` never
      # reaches the Coder (json 3.0 refuses the keyword): it replaces the default encoder table,
      # which renders ::Time, ::DateTime and ::Date as ISO-8601 through core's Instant witness
      # (SERDE-24; design §3.4 makes the wiring the adapter's, not core's).
      #
      # Every reference to Ruby's JSON is `::JSON`: inside this namespace a bare `JSON` is the
      # adapter module (phase 0's shadowing caution; Dexpace/QualifiedCoreConstant enforces it).
      # `::JSON::Coder#load` is `::JSON.parse`'s configured form and is NOT `::JSON.load`, which
      # design §3.4 bans for its `create_additions` hazard (CVE-2020-10663); the two share four
      # letters and nothing else.
      class Codec
        # The option validation, kept beside the class it serves: the allowlist, and the shape of
        # `encoders:`. Private, and not a second public constant in this file.
        module Options
          extend self

          # The options a caller may pass (see the class comment for why an allowlist).
          ALLOWED = %i[max_nesting allow_nan allow_duplicate_key script_safe encoders].freeze

          # @param options [Hash, nil]
          # @return [Hash{Symbol => Object}] the options, or an empty Hash for nil
          # @raise [Dexpace::InvalidArgumentError] on a non-Hash or an unknown key
          def table!(options)
            return {} if options.nil?
            unless options.is_a?(::Hash)
              raise InvalidArgumentError, "options must be a Hash, got #{options.class}"
            end

            unknown = options.keys.reject { |key| ALLOWED.include?(key) }
            return options if unknown.empty?

            raise InvalidArgumentError,
                  "unknown codec option(s) #{unknown.map(&:inspect).join(", ")}; the accepted " \
                  "options are #{ALLOWED.map(&:inspect).join(", ")}"
          end

          # @param encoders [Hash{Module => #call}]
          # @return [Hash{Module => #call}] a frozen copy
          # @raise [Dexpace::InvalidArgumentError] on anything else
          def encoders!(encoders)
            valid = encoders.is_a?(::Hash) &&
                    encoders.all? { |k, v| k.is_a?(::Module) && v.respond_to?(:call) }
            unless valid
              raise InvalidArgumentError,
                    "encoders must be a Hash of Class to #call, got #{encoders.class}"
            end

            encoders.frozen? ? encoders : encoders.dup.freeze
          end
        end
        private_constant :Options

        # SERDE-24's adapter default: date and time values as ISO-8601 strings through core's
        # Instant, never epoch numbers. Exact-class lookup finds DateTime before its superclass
        # Date. Replaceable through `encoders:`.
        DEFAULT_ENCODERS = {
          ::Time => ->(time) { Instant.dexpace_dump(time) },
          ::DateTime => ->(datetime) { Instant.dexpace_dump(datetime.to_time) },
          ::Date => :iso8601.to_proc,
        }.freeze
        private_constant :DEFAULT_ENCODERS

        # SEAM-19/SERDE-2: the media type this codec produces, one frozen value.
        MEDIA_TYPE = MediaType.parse("application/json")
        private_constant :MEDIA_TYPE

        private_class_method :new

        # The one constructor. One positional Hash rather than a `**` splat, as Dexpace::Model#with
        # is spelled: Ruby passes keywords to a method declaring none as one positional Hash, so
        # `Codec.build(max_nesting: 4)` reads as it should while the empty call allocates nothing
        # (Dexpace/NoKeywordSplat) and validation stays this class's.
        #
        # @param options [Hash{Symbol => Object}, nil] `max_nesting:` (Integer), `allow_nan:`,
        #   `allow_duplicate_key:`, `script_safe:` (booleans), `encoders:` (a Hash of Class to
        #   `#call(value) -> native`, replacing the ISO-8601 default table); a nil value means the
        #   default
        # @return [Codec] frozen
        # @raise [Dexpace::InvalidArgumentError] on a non-Hash, an unknown or non-Symbol key, or an
        #   `encoders:` that is not a Hash of Class to callable
        def self.build(options = nil)
          new(options)
        end

        # SERDE-25: a fresh, independently configured instance on every call.
        #
        # @return [Codec]
        def self.default = build

        def initialize(options)
          table = Options.table!(options)
          @encoders = Options.encoders!(table.fetch(:encoders, nil) || DEFAULT_ENCODERS)
          # allow_duplicate_key: false unless the caller says otherwise; strict: true always.
          json_options = { allow_duplicate_key: false }.merge(table.except(:encoders).compact)
          @coder = ::JSON::Coder.new(**json_options, strict: true)
          freeze
        end

        # SEAM-19/SERDE-2: `application/json`, as a Dexpace::MediaType.
        #
        # @return [Dexpace::MediaType]
        def media_type = MEDIA_TYPE

        # SEAM-20's string profile: the value walked to native form by core's Native (SERDE-15,
        # SERDE-19, SERDE-20, SERDE-9's loud refusal) and generated as one UTF-8 String.
        #
        # @param value [Object]
        # @return [String] UTF-8, fresh
        # @raise [Dexpace::Serde::SerializationError] on an unencodable value, chaining the
        #   library's error when the generator raised (SERDE-9, SERDE-10)
        def dump_string(value)
          native = Native.of(value, encoders: @encoders)
          text = @coder.dump(native)
          text.force_encoding(::Encoding::UTF_8) unless text.encoding == ::Encoding::UTF_8
          text
        rescue ::JSON::JSONError => error
          # Inside the rescue, so Ruby chains the library's error as #cause (SERDE-9).
          raise SerializationError, "the value could not be encoded as JSON: #{error.message}"
        end

        # SEAM-20's byte-array profile: the same bytes, BINARY-tagged (§10.13).
        #
        # @param value [Object]
        # @return [String] Encoding::BINARY, fresh
        # @raise [Dexpace::Serde::SerializationError]
        def dump_bytes(value) = dump_string(value).b

        # SEAM-20's streaming profile: writes the bytes into a caller-owned sink and NEVER closes it
        # (SERDE-3).
        #
        # @param value [Object]
        # @param sink [#write] Dexpace::IO::_Sink-shaped
        # @return [Integer] the byte count written
        # @raise [Dexpace::Serde::SerializationError]
        # @raise [Dexpace::InvalidArgumentError] when `sink` does not answer #write
        def dump_to(value, sink)
          unless sink.respond_to?(:write)
            raise InvalidArgumentError, "sink must respond to #write, got #{sink.class}"
          end

          bytes = dump_bytes(value)
          sink.write(bytes)
          bytes.bytesize
        end

        # SEAM-20's buffer profile (SERDE-4): writes at `offset` into a mutable BINARY String and
        # answers the byte count. A range failure is ::IndexError -- distinct from the serde type
        # and chaining nothing -- and bytes outside the written region are untouched. The fit is
        # checked EXPLICITLY, because `String#[]=` with an in-range offset and an over-long payload
        # silently GROWS the target instead of raising (verified fact 12), which is the one
        # behaviour SERDE-4 exists to forbid. The payload is encoded before the check because its
        # length is not knowable otherwise, so a generator failure surfaces as SerializationError
        # and an overflow as IndexError, in that order. Ruby's IO::Buffer is refused (P7-5): it
        # warns through Warning.warn on construction at every level, and its `#set_string` raises
        # ArgumentError where `String#[]=` raises IndexError.
        #
        # @param value [Object]
        # @param buffer [String] mutable, Encoding::BINARY
        # @param offset [Integer] the start position
        # @return [Integer] the byte count written
        # @raise [::IndexError] when `offset` is out of range or the payload does not fit; `#cause`
        #   is nil even when raised inside a caller's rescue
        # @raise [Dexpace::Serde::SerializationError] on an unencodable value
        # @raise [Dexpace::InvalidArgumentError] on a frozen, non-BINARY or non-String buffer, or a
        #   non-Integer offset -- a wrong KIND of argument, not a wrong range (3a's IO-3 precedent)
        def dump_into(value, buffer, offset: 0)
          buffer!(buffer, offset)
          encoded = dump_bytes(value)
          size = encoded.bytesize
          if offset.negative? || offset > buffer.bytesize || offset + size > buffer.bytesize
            # SERDE-4: distinct from the serde type and NOT chaining the caller's in-flight error
            # (pipeline/7ce4431d's spelling; verified fact 11).
            raise ::IndexError,
                  "#{size} bytes at offset #{offset} do not fit a #{buffer.bytesize}-byte buffer",
                  cause: nil
          end

          buffer[offset, size] = encoded
          size
        end

        # SEAM-21's decode: drains the caller's source to EOF, validates the text as UTF-8, parses
        # it with the private engine and hands the parsed value to the witness with a root
        # DecodeContext naming it. Closes nothing (SERDE-3; design §10.12's third ownership rule,
        # which phase 3 left to this layer).
        #
        # The source is read with 3a's `#read_utf8` -- unconditionally UTF-8, because RFC 8259 §8.1
        # fixes JSON text as UTF-8 for interchange, and this method takes a source, not a response,
        # so it has no declared charset to consult -- guarded incrementally by
        # Dexpace::IO.max_materialized_bytes (P7-1: the whole text IS materialised; a body above the
        # ceiling raises Dexpace::StreamError, an ::IOError, unwrapped). A raw IO answering `#read`
        # is wrapped in a BufferedSource for the same read and the same guard; the wrapper is
        # dropped, never closed, so the caller's IO stays open. The UTF-8 validation is P7-6: 3a's
        # `#read_utf8` retags without validating and `::JSON.parse` accepts invalid UTF-8, returning
        # a UTF-8-tagged String whose `#valid_encoding?` is false, so without this line a caller
        # receives a String that claims an encoding it does not have.
        #
        # The parse is rescued as `::JSON::JSONError` and nothing wider: its ancestry is
        # [ParserError, JSONError, StandardError] with IOError nowhere in it (verified fact 4), so a
        # Dexpace::StreamError structurally cannot be caught here and SERDE-12 holds without a
        # discipline. The witness's own DeserializationError passes through unwrapped.
        #
        # @param source [Dexpace::IO::BufferedSource, #read] a caller-owned stream
        # @param witness [Object] the target: a class answering .dexpace_load, or a combinator
        # @return [Object] the witness's decode
        # @raise [Dexpace::Serde::DeserializationError] on invalid UTF-8, malformed JSON (chaining
        #   the parser's error), or a shape mismatch (from the witness, naming the target)
        # @raise [Dexpace::StreamError] unwrapped, from the source
        # @raise [Dexpace::InvalidArgumentError] on a non-witness or a non-stream source
        def load(source, witness)
          Dexpace::Serde.witness!(witness)
          text = drain(source)
          unless text.valid_encoding?
            raise DeserializationError,
                  "the payload is not valid UTF-8 (RFC 8259 §8.1); refusing to parse it"
          end

          parsed = parse(text)
          # SERDE-13: the root frame carries the TARGET so a top-level null names Pet, not Hash;
          # nothing screens for nil here because SERDE-20's Tristate.of and Nullable.of want one.
          witness.dexpace_load(parsed, DecodeContext.root(target: witness))
        end

        private

        # P7-5 and 3a's precedent: a wrong KIND of argument is an argument error, never a range one.
        def buffer!(buffer, offset)
          unless buffer.is_a?(::String) && !buffer.frozen? && buffer.encoding == ::Encoding::BINARY
            raise InvalidArgumentError, "buffer must be a mutable Encoding::BINARY String"
          end
          return if offset.is_a?(::Integer)

          raise InvalidArgumentError, "offset must be an Integer, got #{offset.class}"
        end

        def drain(source)
          return source.read_utf8 if source.respond_to?(:read_utf8)
          if source.respond_to?(:read) || source.respond_to?(:readpartial)
            return Dexpace::IO::BufferedSource.wrapping(source).read_utf8
          end

          raise InvalidArgumentError,
                "source must be a Dexpace::IO::BufferedSource or an IO answering #read, " \
                "got #{source.class}"
        end

        # ::JSON::Coder#load, which is ::JSON.parse's configured form and NOT ::JSON.load.
        def parse(text)
          @coder.load(text)
        rescue ::JSON::JSONError => error
          # Inside the rescue, so Ruby chains the parser's error as #cause (SERDE-9, SERDE-27).
          raise DeserializationError, "malformed JSON: #{error.message}"
        end
      end
    end
  end
end
