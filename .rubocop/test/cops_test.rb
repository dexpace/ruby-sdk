# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "cop_case"

# The original five cops and Dexpace/NoKeywordSplat, which between them mechanise CLAUDE.md's
# ban list and NFR-13. One row per case, one generated Minitest method per row, so a failure
# names exactly one input. Phase 2's sixth cop has its own tables in the nested class below,
# because Metrics/ClassLength caps one class at 100 lines and counts a table row as a line.
class CopsTest < CopCase
  D = RuboCop::Cop::Dexpace
  HEADER = "# frozen_string_literal: true\n# SPDX-License-Identifier: MIT\n\n"

  # [cop, source, the fragment the message must carry]
  REJECTED = [
    # NFR-13, and the header shape in docs/knowledge/notes/formatting-and-tooling.md.
    [
      D::SpdxHeader, "# frozen_string_literal: true\n\nmodule Dexpace\nend\n",
      "SPDX-License-Identifier: MIT",
    ],
    [
      D::SpdxHeader, "#{HEADER.sub("MIT", "Apache-2.0")}module Dexpace\nend\n",
      "SPDX-License-Identifier: MIT",
    ],
    [D::SpdxHeader, "# frozen_string_literal: true\n", "SPDX-License-Identifier: MIT"],
    [
      D::SpdxHeader, "# SPDX-License-Identifier: MIT\n# frozen_string_literal: true\n\nX = 1\n",
      "frozen_string_literal",
    ],
    [
      D::SpdxHeader,
      "# frozen_string_literal: true\n# SPDX-License-Identifier: MIT\nmodule Dexpace\nend\n",
      "must be blank",
    ],

    # Design §3.5: Time.parse guesses at ambiguous input; HTTP dates are parsed explicitly.
    [D::NoTimeParse, "Time.parse(header)\n", "banned"],
    [D::NoTimeParse, "Date.parse(header)\n", "banned"],
    [D::NoTimeParse, "DateTime.parse(header)\n", "banned"],
    [D::NoTimeParse, "::Time.parse(header)\n", "banned"],
    [D::NoTimeParse, "Time&.parse(header)\n", "banned"],

    # Design §3.5: DEFAULT_PARSER changed meaning at exactly Ruby 3.4.0, which straddles the
    # supported floor.
    [D::NoUriDefaultParser, "URI::DEFAULT_PARSER.parse(raw)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "URI.parse(raw)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "URI.join(base, rel)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "URI.split(raw)\n", "RFC3986_PARSER"],
    # Kernel#URI is URI.parse for a String argument -- the most common spelling of the ban.
    [D::NoUriDefaultParser, "URI(\"https://example.com\")\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "Kernel.URI(raw)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "::Kernel.URI(raw)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "URI&.parse(raw)\n", "RFC3986_PARSER"],
    # URI::Parser is URI::RFC2396_Parser on 3.2/3.3 and URI::RFC3986_Parser from 3.4 -- the same
    # straddle of the floor as DEFAULT_PARSER, under another name.
    [D::NoUriDefaultParser, "URI::Parser.new.parse(raw)\n", "RFC3986_PARSER"],
    [D::NoUriDefaultParser, "::URI::Parser.new\n", "RFC3986_PARSER"],

    # HTTP-13: header folding is ASCII. "I".downcase(:turkic) is "ı".
    [D::NoLocaleCaseFold, "name.downcase(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name.upcase(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name.capitalize(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name.swapcase(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name.downcase!(:fold)\n", "no argument"],
    [D::NoLocaleCaseFold, "a.casecmp?(b)\n", "ASCII-only"],
    # Safe navigation is a `csend` node, not a `send`, and reaches a cop only through on_csend.
    [D::NoLocaleCaseFold, "name&.downcase(:turkic)\n", "no argument"],
    [D::NoLocaleCaseFold, "name&.casecmp?(other)\n", "ASCII-only"],

    # Design §8.3: an async interrupt can land inside an `ensure` releasing a pooled connection.
    [D::NoThreadInterrupt, "Timeout.timeout(5) { read }\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "worker_thread.raise(Interrupt)\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "worker_thread.kill\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "Thread.current.terminate\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "worker_thread.exit\n", "banned repository-wide"],
    # `@thread&.kill` in a `close` is the ordinary spelling, and exactly where the interrupt
    # lands inside an `ensure`; `threads.each(&:kill)` has no receiver to match by name.
    [D::NoThreadInterrupt, "@thread&.kill\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "@thread&.terminate\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "worker_thread&.raise(Interrupt)\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "Thread.current&.kill\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "Timeout&.timeout(5) { read }\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "threads.each(&:kill)\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "workers.each(&:terminate)\n", "banned repository-wide"],
    [D::NoThreadInterrupt, "threads.map(&:exit)\n", "banned repository-wide"],

    # OBS-25 / OBS-1: a `**` splat allocates a Hash per call even when no keyword is passed, so
    # a no-op path written with one cannot allocate nothing.
    [D::NoKeywordSplat, "module Dexpace\n  def emit(event, **attributes)\n  end\nend\n", "OBS-25"],
    [D::NoKeywordSplat, "module Dexpace\n  def self.build(**options)\n  end\nend\n", "OBS-25"],
    [D::NoKeywordSplat, "def m(x, **)\nend\n", "OBS-25"],
    [D::NoKeywordSplat, "def wrap(event, **kw)\n  inner(event, **kw)\nend\n", "OBS-25"],
  ].freeze

  # [cop, source] -- the sanctioned form each ban points at.
  ACCEPTED = [
    [D::SpdxHeader, "#{HEADER}module Dexpace\nend\n"],
    [D::NoTimeParse, "Time.httpdate(header)\n"],
    [D::NoTimeParse, "MediaType.parse(header)\n"],
    [D::NoUriDefaultParser, "URI::RFC3986_PARSER.parse(raw)\n"],
    [D::NoUriDefaultParser, "URI::RFC3986_PARSER.join(base, rel)\n"],
    [D::NoUriDefaultParser, "URI::HTTP.build(host: host)\n"],
    # An explicit grammar is a choice, not the moving default.
    [D::NoUriDefaultParser, "URI::RFC2396_Parser.new.parse(raw)\n"],
    [D::NoUriDefaultParser, "URI::RFC2396_PARSER.parse(raw)\n"],
    [D::NoLocaleCaseFold, "name.downcase\n"],
    [D::NoLocaleCaseFold, "a.casecmp(b).zero?\n"],
    [D::NoLocaleCaseFold, "name&.downcase\n"],
    [D::NoThreadInterrupt, "raise ArgumentError, \"url is required\"\n"],
    [D::NoThreadInterrupt, "http.read_timeout = deadline.remaining\n"],
    [D::NoThreadInterrupt, "sockets.each(&:close)\n"],
    [D::NoThreadInterrupt, "connection&.close\n"],
    [D::NoKeywordSplat, "module Dexpace\n  def emit(event, attributes: nil)\n  end\nend\n"],
    [D::NoKeywordSplat, "def build(method:, url:, headers:, body:)\nend\n"],
    [D::NoKeywordSplat, "class Foo\n  private\n\n  def m(**opts)\n  end\nend\n"],
    [D::NoKeywordSplat, "class Foo\n  private def m(**opts)\n  end\nend\n"],
    [D::NoKeywordSplat, "class Foo\n  def self.m(**opts)\n  end\n  private_class_method :m\nend\n"],
  ].freeze

  REJECTED.each_with_index do |(cop, source, fragment), index|
    test "#{cop.badge} rejects case #{index}: #{source.lines.first.strip}" do
      assert_offense(cop, source, fragment)
    end
  end

  ACCEPTED.each_with_index do |(cop, source), index|
    test "#{cop.badge} accepts case #{index}: #{source.lines.first.strip}" do
      assert_no_offense(cop, source)
    end
  end

  # Design §9 Addendum A1 (phase 2): a bare Thread/Queue/Mutex/JSON inside Dexpace::Async or
  # Dexpace::Serde rebinds to the adapter gem's constant the moment that gem is required, and
  # core's own suite never requires it. The compact `module Dexpace::Async` form is the same
  # lexical path and is flagged too; one SHADOWED list serves both namespaces, so a bare JSON
  # inside Dexpace::Async is flagged even though only Dexpace::Serde reopens JSON.
  class QualifiedCoreConstantTest < CopCase
    ASYNC = "module Dexpace\n  module Async\n    %s\n  end\nend\n"
    SERDE = "module Dexpace\n  module Serde\n    %s\n  end\nend\n"
    NESTED = "module Dexpace\n  module Async\n    class Completer\n      def initialize\n        " \
             "@gate = %s\n      end\n    end\n  end\nend\n"

    # [source, the fragment the message must carry]
    REJECTED = [
      [format(ASYNC, "Thread.new"), "Write `::Thread` here"],
      [format(ASYNC, "Queue.new"), "Write `::Queue` here"],
      [format(ASYNC, "Mutex.new"), "Write `::Mutex` here"],
      [format(ASYNC, "SizedQueue.new(2)"), "Write `::SizedQueue` here"],
      [format(ASYNC, "ConditionVariable.new"), "Write `::ConditionVariable` here"],
      [format(SERDE, "JSON.generate(value)"), "Write `::JSON` here"],
      ["module Dexpace::Async\n  Thread.new\nend\n", "Write `::Thread` here"],
      [format(ASYNC, "JSON.parse(text)"), "Write `::JSON` here"],
      # A class nested inside the namespace is still lexically inside it, and `Thread::Queue`
      # is a bare `Thread` with `Queue` hanging off it.
      [format(NESTED, "Thread::Queue.new"), "Write `::Thread` here"],
    ].freeze

    # The accepted half is what proves the cop does not reject every occurrence of the six names.
    ACCEPTED = [
      format(ASYNC, "::Thread.new"),
      format(ASYNC, "::Queue.new"),
      format(SERDE, "::JSON.generate(value)"),
      "module Dexpace\n  module Transport\n    Thread.new\n  end\nend\n",
      "Thread.new\n",
      format(ASYNC, "Dexpace::Async::Thread.new"),
      format(NESTED, "::Thread::Queue.new"),
      format(SERDE, "class << self\n      def a = ::JSON\n    end"),
    ].freeze

    REJECTED.each_with_index do |(source, fragment), index|
      test "rejects case #{index}: #{source.lines.first.strip}" do
        assert_offense(D::QualifiedCoreConstant, source, fragment)
      end
    end

    ACCEPTED.each_with_index do |source, index|
      test "accepts case #{index}: #{source.lines.first.strip}" do
        assert_no_offense(D::QualifiedCoreConstant, source)
      end
    end
  end
end
