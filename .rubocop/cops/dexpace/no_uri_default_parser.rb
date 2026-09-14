# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Design §3.5. What `URI::DEFAULT_PARSER` *is* changed at exactly Ruby 3.4.0, which
      # straddles the supported floor of 3.2, so a parse that relies on the default resolves
      # differently on two supported interpreters. Every parse and every resolution pins
      # `URI::RFC3986_PARSER`.
      #
      # `URI::Parser` is the same straddle under another name: it is `URI::RFC2396_Parser` on
      # 3.2 and 3.3 and `URI::RFC3986_Parser` from 3.4, so `URI::Parser.new` is banned with the
      # constant. `URI::RFC2396_Parser` and `URI::RFC2396_PARSER` name a grammar explicitly and
      # are not.
      #
      # `Kernel#URI` is the most common spelling of the parse this cop exists to ban: for a
      # String argument it is `URI.parse(uri)` (uri/common.rb), which routes through the default
      # parser like the rest of the family, so `URI(raw)` and `Kernel.URI(raw)` are offences too.
      class NoUriDefaultParser < Base
        MSG = "`%<offender>s` routes through the default URI parser (URI::DEFAULT_PARSER, " \
              "alias URI::Parser), whose meaning changed at Ruby 3.4.0. Pin URI::RFC3986_PARSER " \
              "explicitly (design §3.5)."
        RESTRICT_ON_SEND = %i[parse join split extract regexp escape unescape URI].freeze

        # @!method default_parser_const?(node)
        def_node_matcher :default_parser_const?, <<~PATTERN
          (const (const {nil? cbase} :URI) {:DEFAULT_PARSER :Parser})
        PATTERN

        # @!method uri_module_call?(node)
        def_node_matcher :uri_module_call?, <<~PATTERN
          ({send csend} (const {nil? cbase} :URI)
                {:parse :join :split :extract :regexp :escape :unescape} ...)
        PATTERN

        # @!method kernel_uri_call?(node)
        def_node_matcher :kernel_uri_call?, <<~PATTERN
          ({send csend} {nil? (const {nil? cbase} :Kernel)} :URI ...)
        PATTERN

        def on_const(node)
          return unless default_parser_const?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end

        def on_send(node)
          return unless uri_module_call?(node) || kernel_uri_call?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end
        alias on_csend on_send
      end
    end
  end
end
