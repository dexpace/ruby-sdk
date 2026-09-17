# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Proxy
    # One non-proxy host glob (CFG-23), compiled ONCE at construction -- "Patterns SHOULD be
    # compiled once at construction, not per lookup" -- and matched against a host as a
    # full-string, case-insensitive match. The translation is CFG-23's four rules: `*` is any run
    # of characters, `?` is exactly one, everything else is Regexp.escape'd, and the pattern is
    # anchored \A..\z. \z and never \Z, because \Aabc\Z matches "abc\n" and a full-string match
    # that accepts a trailing newline is not one; no /m, because `.*` stopping at \n is what keeps
    # *.example.com from matching "evil.com\n.example.com" -- a tolerance turned into a bypass of
    # the very check the pattern performs. The timeout is per-pattern, never Regexp.timeout.
    #
    # A one-member Data: the glob is the value, and the compiled Regexp is an instance variable
    # set in the constructor rather than a second member, so equality and #with are over the glob
    # alone and Model#with -- which routes through .build on every Ruby -- recompiles it. (The
    # design's two-member shape carried the matcher as a member .build had to accept and ignore.)
    #
    # Reopens `class Proxy`, which proxy.rb declares and requires this file from; it never appears
    # in lib/dexpace.rb.
    class HostPattern < Data.define(:glob)
      include Model

      private_class_method :new

      # @param glob [String] the pattern, non-blank
      def initialize(glob:)
        text = Model.required!("glob", glob).to_s
        raise InvalidArgumentError, "glob is required" if text.strip.empty?

        @matcher = translate(text)
        super(glob: Model.frozen_string(text))
      end

      # @param glob [String]
      # @return [HostPattern]
      # @raise [Dexpace::InvalidArgumentError] on a nil or blank glob
      def self.build(glob:)
        new(glob: glob)
      end

      # The parse-constructor.
      #
      # @param glob [String] a wildcard pattern such as *.example.com
      # @return [HostPattern]
      def self.of(glob)
        build(glob: glob)
      end

      # Whether the host matches, as given: stripping it first would defeat the \z anchor, since
      # "evil.com\n".strip is "evil.com". nil never matches.
      #
      # @param host [String, nil]
      # @return [Boolean]
      def matches?(host)
        return false if host.nil?

        @matcher.match?(host.to_s)
      end

      private

      # The compiled Regexp -- private, so the surface carries the glob and the predicate and not
      # the mechanism.
      attr_reader :matcher

      # CFG-23's translation, once per pattern.
      def translate(glob)
        source = glob.each_char.map do |char|
          case char
          when "*" then ".*"
          when "?" then "."
          else ::Regexp.escape(char)
          end
        end.join
        ::Regexp.new("\\A#{source}\\z", ::Regexp::IGNORECASE, timeout: 1.0)
      end
    end
  end
end
