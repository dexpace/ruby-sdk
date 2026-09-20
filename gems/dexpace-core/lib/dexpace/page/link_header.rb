# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"

module Dexpace
  class Page
    # PAGE-18 and PAGE-20: the RFC 8288 link-value grammar, as a character-level state machine, and
    # the one question the Link strategy asks of it -- the first link-value whose `rel` carries the
    # token `next`.
    #
    # Not a regexp, and that is spec-forced boundary 22 rather than a style preference: RFC 8288's
    # grammar is not regular. A comma inside the angle-bracketed URI-reference and a comma inside a
    # quoted parameter value must not split link-values, a semicolon inside a quoted value must not
    # split parameters, and a quoted-pair escape (`\"`) must be honoured -- exactly the inputs
    # PAGE-18's conformance clause names, and exactly where a pattern that appeared to work would
    # fail. So the per-pattern-timeout constraint is discharged by not writing the pattern, the
    # route design §6.3 takes for WWW-Authenticate; no Regexp is compiled in this file and the
    # suite scans for one. The `rel` value is accepted quoted or unquoted, split on space and tab
    # into relation types, and each token compared through the no-argument `downcase`
    # (Dexpace/NoLocaleCaseFold) -- the one fold site in the subsystem. A parameter NAME is folded
    # too, so `REL=next` is `rel=next` (RFC 8288 §3: parameter names are case-insensitive), and
    # only the FIRST `rel` parameter of a link-value is read: RFC 8288 §3.3 says `rel` MUST NOT
    # appear more than once and occurrences after the first MUST be ignored, so
    # `<u>; rel="prev"; rel="next"` is a prev link and never a next one (P7-116).
    #
    # It never raises. Malformed input -- a value with no angle brackets, a reference never closed,
    # a quoted string never closed, an escape at the very end -- yields the link-values scanned so
    # far and drops the broken parameter, which the strategy reads as end-of-stream (PAGE-18's
    # "absence of a rel=next segment"); a blank target `<>` comes back as "" and is the strategy's
    # P7-5. Several header instances are joined with ", " first, which is PAGE-20's normalisation
    # by concatenation: the grammar is the same whether the server sent one instance or three. A
    # private_constant, asserted at LinkStrategy's call site and through const_get in its own
    # suite, with a sig/ mirror because the strict `core` Steep target types every file under lib/.
    module LinkHeader
      extend self

      OWS = [" ", "\t"].freeze
      # What separates link-values from one another, with the whitespace around them.
      SEPARATORS = [" ", "\t", ","].freeze
      # What ends a parameter name or an unquoted parameter value.
      TOKEN_END = [" ", "\t", ";", ",", "="].freeze
      private_constant :OWS, :SEPARATORS, :TOKEN_END

      # @param values [Array<String>, nil] the Link header's instances, as Headers#[] returns them
      # @return [String, nil] the first rel=next URI-reference, raw, or nil for end-of-stream
      def next_target(values)
        return nil if values.nil? || values.empty?

        link_values(values.join(", ")).each do |target, params|
          rel = params.find { |name, _value| name == "rel" }
          return target if !rel.nil? && next_token?(rel[1])
        end
        nil
      end

      private

      # PAGE-18: `rel` lists space- or tab-separated relation types; the match is the whole token,
      # case-insensitively. A bare `split` is awk-style whitespace splitting and compiles nothing.
      def next_token?(value)
        value.split.any? { |token| token.downcase == "next" }
      end

      # Every `[target, params]` pair in order, stopping at the first malformed link-value: one
      # that does not open with `<` or never closes its `>`.
      def link_values(text)
        results = [] #: Array[[String, Array[[String, String]]]]
        index = skip(text, 0, SEPARATORS)
        while index < text.length && text[index] == "<"
          close = text.index(">", index + 1)
          break if close.nil?

          target = text[(index + 1)...close] || ""
          params, index = parse_params(text, close + 1)
          results << [target, params]
          index = skip(text, index, SEPARATORS)
        end
        results
      end

      # The index of the first character at or after `index` that is not in `set`.
      def skip(text, index, set)
        index += 1 while index < text.length && set.include?(text[index])
        index
      end

      # The `; name=value` list after a `>`, up to the next top-level comma or the end of the text.
      # Anything other than `;` or `,` where a separator is expected ends this link-value's
      # parameters at the next comma.
      #
      # @return [Array(Array<Array(String, String)>, Integer)] the pairs, and where to resume
      def parse_params(text, index)
        params = [] #: Array[[String, String]]
        loop do
          index = skip(text, index, OWS)
          return [params, index] if index >= text.length || text[index] == ","
          return [params, text.index(",", index) || text.length] unless text[index] == ";"

          pair, index = parse_param(text, index + 1)
          params << pair unless pair.nil?
        end
      end

      # One `name` or `name=value` after a `;`; nil for an empty name or an unterminated quoted
      # value, either of which is dropped rather than raised on.
      #
      # @return [Array(Array(String, String), Integer)] the pair (or nil), and where to resume
      def parse_param(text, index)
        name, index = read_token(text, skip(text, index, OWS))
        index = skip(text, index, OWS)
        value = "" #: String?
        value, index = read_value(text, skip(text, index + 1, OWS)) if text[index] == "="
        return [nil, index] if name.empty? || value.nil?

        pair = [name.downcase, value] #: [String, String]
        [pair, index]
      end

      def read_value(text, index)
        text[index] == '"' ? read_quoted(text, index + 1) : read_token(text, index)
      end

      def read_token(text, index)
        start = index
        index += 1 while index < text.length && !TOKEN_END.include?(text[index])
        [text[start...index] || "", index]
      end

      # From just after the opening quote to just after the closing one, unescaping quoted-pairs.
      # An unterminated string, or an escape as the very last character, is nil and consumes the
      # rest: there is no grammar left to honour.
      def read_quoted(text, index)
        value = +""
        while index < text.length
          char = text[index]
          return [value, index + 1] if char == '"'

          if char == "\\"
            return [nil, text.length] if index + 1 >= text.length

            index += 1
            char = text[index]
          end
          value << char.to_s
          index += 1
        end
        [nil, index]
      end
    end
    private_constant :LinkHeader
  end
end
