# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require "stringio"

# The ceiling half of the body-logging caps phase 3b postponed to phase 5 (IO-9 and BODY-32's
# cross-reference rows): Dexpace::IO.max_materialized_bytes reads Keys::MAX_MATERIALIZED_BYTES
# through the chain on every call, with the frozen constant as the default, and phase 3a's and
# 3b's five value-readers now read it rather than the constant -- so Dexpace.configure and
# .reset_config! govern the live ceiling. No `ceiling:` keyword exists anywhere.
module IOCeilingTest
  KEY = Dexpace::Configuration::Keys::MAX_MATERIALIZED_BYTES

  # The source itself.
  class SourceTest < DexpaceTestCase
    def teardown
      Dexpace.reset_config!
      super
    end

    test "materialisation ceiling: the function reads the configured ceiling on every call" do
      assert_equal(Dexpace::IO::MAX_MATERIALIZED_BYTES, Dexpace::IO.max_materialized_bytes)

      custom = Dexpace::Configuration.builder
        .tap { |b| b.env_source = Dexpace::Configuration::Sources::NONE }
        .override(KEY, "1048576")
        .build

      assert_equal(1_048_576, Dexpace::IO.max_materialized_bytes(custom))

      # Not memoised: a Dexpace.configure after the first read is effective, which is the
      # context-store-cap consequence avoided where it is avoidable (open question 5).
      Dexpace.configure { |c| c.override(KEY, "2097152") }

      assert_equal(2_097_152, Dexpace::IO.max_materialized_bytes)

      Dexpace.reset_config!

      assert_equal(Dexpace::IO::MAX_MATERIALIZED_BYTES, Dexpace::IO.max_materialized_bytes)
    end

    test "materialisation ceiling: an unparseable or non-positive ceiling falls back to 64 MiB" do
      ["sixty-four megs", "0", "-1", ""].each do |value|
        Dexpace.configure { |c| c.override(KEY, value) }

        assert_equal(Dexpace::IO::MAX_MATERIALIZED_BYTES, Dexpace::IO.max_materialized_bytes,
                     value.inspect,)
      end
    end

    test "materialisation ceiling: the constant stays 64 MiB, frozen, and takes no keyword" do
      assert_equal(64 * 1024 * 1024, Dexpace::IO::MAX_MATERIALIZED_BYTES)
      assert_predicate(Dexpace::IO::MAX_MATERIALIZED_BYTES, :frozen?)
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::IO.max_materialized_bytes(nil) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::IO.max_materialized_bytes(:cfg) }
    end
  end

  # The five readers, driven through a configured ceiling small enough to observe.
  class ReadersTest < DexpaceTestCase
    def teardown
      Dexpace.reset_config!
      super
    end

    test "IO-9: TypedReads' materialisation guard honours a configured ceiling, naming the key" do
      Dexpace.configure { |c| c.override(KEY, "8") }
      source = Dexpace::IO::BufferedSource.of_bytes("0123456789abcdef")

      error = assert_raises(Dexpace::StreamError) { source.read_exactly(9) }

      assert_includes(error.message, "the limit is 8 bytes")
      assert_includes(error.message, KEY)
      assert_equal("01234567", source.read_exactly(8))

      Dexpace.reset_config!

      assert_equal("89abcdef", source.read_exactly(8))
    end

    test "IO-9: Buffer#snapshot refuses over a configured ceiling and allows once it is raised" do
      buffer = Dexpace::IO::Buffer.new
      buffer.write("0123456789")
      Dexpace.configure { |c| c.override(KEY, "4") }

      assert_raises(Dexpace::StreamError) { buffer.snapshot }

      Dexpace.configure { |c| c.override(KEY, "10") }

      assert_equal("0123456789", buffer.snapshot)
    end

    test "BODY-32: Body.buffer_bounded clamps a cap to the CONFIGURED ceiling, not the constant" do
      Dexpace.configure { |c| c.override(KEY, "4") }

      unbounded = Dexpace::Body.buffer_bounded(response_body, cap: ::Float::INFINITY)
      below = Dexpace::Body.buffer_bounded(response_body, cap: 3)
      above = Dexpace::Body.buffer_bounded(response_body, cap: 1_000)

      assert_equal(4, unbounded.content_length)
      assert_equal(3, below.content_length)
      assert_equal(4, above.content_length)
    end

    def response_body
      Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes("0123456789"))
    end

    test "BODY-9: StreamBody#replayable? compares the known length to the configured ceiling" do
      io = StringIO.new("0123456789")
      body = Dexpace::Body.stream(io, content_length: 10)

      assert_predicate(body, :replayable?)

      Dexpace.configure { |c| c.override(KEY, "4") }

      refute_predicate(body, :replayable?)
    end

    test "HTTP-46: BufferBody#== compares beyond the configured ceiling by identity only" do
      left = Dexpace::Body.buffer(Dexpace::IO::Buffer.new.tap { |b| b.write("0123456789") })
      right = Dexpace::Body.buffer(Dexpace::IO::Buffer.new.tap { |b| b.write("0123456789") })

      assert_equal(left, right)

      Dexpace.configure { |c| c.override(KEY, "4") }

      refute_equal(left, right)
    end
  end
end
