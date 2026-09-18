# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "strscan"

require_relative "../auth"
require_relative "challenge"

module Dexpace
  module Auth
    # AUTH-12, AUTH-13: the RFC 7235 challenge-list parser, as a StringScanner-driven state
    # machine and never a regexp over the grammar -- the grammar is not regular (a quoted-string
    # may hold the list's own delimiters), and a hostile WWW-Authenticate must not be able to
    # drive a backtracking engine (design §6.3). The eight patterns it does use are fixed
    # character classes with no alternation inside a repetition, compiled with the tree's
    # per-pattern timeout; every loop iteration consumes at least one byte, so the parse is
    # linear in the input and the suite measures it rather than trusting the claim.
    #
    # Public, like Dexpace::HTTPDate: a caller writing a challenge handler for a scheme this SDK
    # does not implement needs the same lenient parser, and it carries no credential-shaped
    # state.
    #
    # The grammar's one real ambiguity is settled here once. `1#challenge` is a comma-separated
    # list whose elements are `auth-scheme [ 1*SP ( token68 / #auth-param ) ]`, so a comma may
    # separate two PARAMETERS of one challenge or two CHALLENGES, and the only thing that tells
    # them apart is what follows the next token: `name=` continues the current challenge,
    # a bare token opens a new one. Empty list elements (`,,`) are skipped, as RFC 7230 §7
    # requires of any recipient. A token68 is taken only when it runs to a list boundary (the
    # end of input, or optional whitespace and a comma), because `realm=` is also a token68
    # prefix and `Digest realm="r"` must not lose its realm to that reading.
    #
    # Leniency (AUTH-13): the parser never raises. Malformed input -- a value that is neither a
    # token nor a quoted-string, a parameter before any scheme, a bare token where a parameter
    # was expected, a character no token starts with -- is skipped to the next TOP-LEVEL comma,
    # walking quoted strings so a comma inside one is not mistaken for the boundary; parameters
    # parsed before the malformed tail stay on the emitted challenge; an unterminated
    # quoted-string takes everything to the end of input as its value.
    module Challenges
      extend self

      # RFC 7230's tchar set: the auth-scheme and every parameter name and token value.
      TOKEN = Regexp.new("[!#$%&'*+\\-.^_`|~0-9A-Za-z]+", timeout: 1.0)
      # RFC 7235's token68: TOKEN's letters and digits plus `-._~+/`, then base64 padding,
      # which TOKEN excludes -- so `Bearer dGhl…==` is not readable as a parameter.
      TOKEN68 = Regexp.new("[A-Za-z0-9\\-._~+/]+=*", timeout: 1.0)
      # One or more list separators with their whitespace: what sits between two elements.
      SEPARATORS = Regexp.new("[ \\t]*,[ \\t,]*", timeout: 1.0)
      # Whitespace, then a list boundary: a comma or the end of input. Checked, never consumed.
      BOUNDARY = Regexp.new("[ \\t]*(?:,|\\z)", timeout: 1.0)
      # A parameter's `=` with the bad whitespace RFC 7235 tolerates on either side.
      EQUALS = Regexp.new("[ \\t]*=[ \\t]*", timeout: 1.0)
      # The whitespace between the scheme and what follows it.
      SPACES = Regexp.new("[ \\t]+", timeout: 1.0)
      # Optional whitespace at the start of an element, which recovery leaves behind.
      OWS = Regexp.new("[ \\t]*", timeout: 1.0)
      # The opening quote of a quoted-string.
      QUOTE = Regexp.new("\"", timeout: 1.0)
      private_constant :TOKEN, :TOKEN68, :SEPARATORS, :BOUNDARY, :EQUALS, :SPACES, :OWS, :QUOTE

      # The parse itself: `nil`, blank input and an input of nothing but separators all yield
      # an empty list. The state is one open challenge (`current`) and whether the scanner
      # stands just past a list separator (`boundary`), which is what decides whether a bare
      # token opens a challenge or is a malformed tail.
      #
      # @param header_value [String, nil] a WWW-Authenticate or Proxy-Authenticate value; the
      #   values of a repeated header are joined with ", " before they reach here (RFC 7235 §4.1)
      # @return [Array<Challenge>] in wire order, frozen
      def parse(header_value)
        none = [] #: Array[Challenge]
        return none.freeze if header_value.nil?

        # A value whose bytes are invalid under its own tag -- a Latin-1 realm a transport tagged
        # UTF-8 -- makes StringScanner#scan and String#downcase raise ArgumentError, and AUTH-13
        # says this never raises: such a value is scanned as bytes (verified on 3.2.11, 3.4.10
        # and 4.0.6). A valid one keeps its tag, so its values come back as the caller's Strings.
        text = header_value.valid_encoding? ? header_value : header_value.b
        return none.freeze if text.strip.empty?

        parser = Parser.new(text)
        parser.run
        parser.challenges.freeze
      end

      # The state machine, one instance per parse so the module stays stateless. A private
      # class rather than a set of module functions threading three arguments.
      class Parser
        attr_reader :challenges

        def initialize(input)
          @scanner = ::StringScanner.new(input)
          @challenges = []
          @scheme = nil #: String?
          @params = {} #: Hash[String, String]
          @boundary = true
        end

        # Every iteration consumes at least one byte: each branch scans, skips or recovers.
        def run
          until @scanner.eos?
            @scanner.skip(OWS)
            @boundary = true if @scanner.skip(SEPARATORS)
            break if @scanner.eos?

            step
          end
          emit
        end

        private

        # One list element, or one malformed tail: a parameter, a scheme at a list boundary, or
        # -- a character no token starts with, a bare token where a parameter was expected --
        # a recovery.
        def step
          name = @scanner.scan(TOKEN)
          if !name.nil? && @scanner.skip(EQUALS)
            parameter(name)
          elsif !name.nil? && @boundary
            open_challenge(name)
          else
            recover
          end
        end

        # `name=value`: a parameter of the open challenge. Before any scheme it is malformed.
        def parameter(name)
          return recover if @scheme.nil?

          value = scan_value
          return recover if value.nil?

          @params[name] = value # folded once, at Challenge.build
          @boundary = false
          # A value must be followed by a boundary; anything else is the malformed tail.
          recover unless @scanner.match?(BOUNDARY)
        end

        # A scheme opens a challenge, closing the previous one. What follows the whitespace is
        # a token68 only when it runs to a boundary; otherwise the parameters (or the malformed
        # tail) are read by the next iterations.
        def open_challenge(name)
          emit
          @scheme = name # folded once, at Challenge.build
          @params = {}
          @boundary = false
          @scanner.skip(SPACES)
          position = @scanner.pos
          bare = @scanner.scan(TOKEN68)
          if bare && @scanner.match?(BOUNDARY)
            @params[Challenge::TOKEN68] = bare
          else
            @scanner.pos = position
          end
        end

        # A token, or an unquoted, unescaped quoted-string; nil when the input is neither.
        def scan_value
          return @scanner.scan(TOKEN) unless @scanner.skip(QUOTE)

          value = +""
          until @scanner.eos?
            char = @scanner.getch
            if char == "\\" && !@scanner.eos?
              value << @scanner.getch.to_s
            elsif char == '"'
              return value.freeze
            else
              value << char.to_s
            end
          end
          value.freeze # unterminated: the value runs to the end of input (AUTH-13)
        end

        # AUTH-13: skip to the next TOP-LEVEL comma, walking any quoted-string on the way so a
        # comma inside one is not read as the boundary. Consumes at least one byte, or ends
        # the input.
        def recover
          until @scanner.eos?
            char = @scanner.getch
            if char == '"'
              skip_quoted
            elsif char == ","
              break
            end
          end
          @boundary = true
        end

        # Inside a quoted-string during recovery: to the closing quote, honouring escapes.
        def skip_quoted
          until @scanner.eos?
            char = @scanner.getch
            if char == "\\"
              @scanner.getch
            elsif char == '"'
              return
            end
          end
        end

        # Close the open challenge, if any, onto the list.
        def emit
          scheme = @scheme
          return if scheme.nil?

          @challenges << Challenge.build(scheme: scheme, params: @params)
          @scheme = nil
          @params = {}
        end
      end
      private_constant :Parser
    end
  end
end
