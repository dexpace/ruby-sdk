# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "stage"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # The sixteen stages and their total ordering (PIPE-1, PIPE-2, PIPE-3; P4-31), the one table
    # both runtimes flatten through (PIPE-28, design §5.3).
    #
    # PIPE-2's chain -- REDIRECT, RETRY, AUTH, LOGGING, SERDE, outer to inner, an outermost
    # pre-redirect slot and a terminal SEND hop -- with PIPE-3 taken literally: a "pre" slot before
    # and a "post" slot after each pillar. PRE_REDIRECT is REDIRECT's own pre-slot and is also
    # PIPE-2's named outermost slot, the one place a step observes only the single terminal
    # response (PIPE-37). POST_REDIRECT and PRE_RETRY are adjacent and order-equivalent and are
    # kept as two constants because they express two intents, "after the redirect loop" and
    # "before the retry loop". Order keys are sparse by 100 so a later specification revision can
    # insert a stage without renumbering.
    #
    # ALL is the ordering, and it is the ONLY ordering: flattening walks ALL's positions and
    # nothing reads #order at run time (a Data cannot be sorted; see Stage). PILLARS is the five
    # configurable pillars, SEND excluded, which is also the whole set of stages whose occupant may
    # fork and write cursor-scoped state (R10, R11).
    module Stages
      # Stage.new is private (P4-32) and this module is the one place the sixteen are minted, so
      # the constructor is reached through the one `send` in the subsystem rather than by leaving
      # `new` public until the table is built.
      def self.mint(name, order, pillar: false, terminal: false)
        Stage.send(:new, name: name, order: order, pillar: pillar, terminal: terminal)
      end
      private_class_method :mint

      # PIPE-2's outermost pre-redirect slot, outside both the redirect and retry loops: where a
      # step that must observe only the single terminal response is installed (PIPE-37).
      PRE_REDIRECT = mint(:pre_redirect, 100)
      # The redirect pillar (PIPE-2). Its occupant forks per hop and writes the cross-origin
      # marker into this stage's cursor slot, which AUTH reads (design §6.2, §10.15; phase 6).
      REDIRECT = mint(:redirect, 200, pillar: true)
      # After the redirect loop.
      POST_REDIRECT = mint(:post_redirect, 300)
      # Before the retry loop.
      PRE_RETRY = mint(:pre_retry, 400)
      # The retry pillar (PIPE-2).
      RETRY = mint(:retry, 500, pillar: true)
      # After the retry loop.
      POST_RETRY = mint(:post_retry, 600)
      # Before the authentication pillar.
      PRE_AUTH = mint(:pre_auth, 700)
      # The authentication pillar (PIPE-2).
      AUTH = mint(:auth, 800, pillar: true)
      # After the authentication pillar.
      POST_AUTH = mint(:post_auth, 900)
      # Before the logging pillar.
      PRE_LOGGING = mint(:pre_logging, 1000)
      # The logging pillar (PIPE-2). A slot for a step, not a `logger` require: the sink is a duck
      # type (design §8.1).
      LOGGING = mint(:logging, 1100, pillar: true)
      # After the logging pillar.
      POST_LOGGING = mint(:post_logging, 1200)
      # Before the serde pillar.
      PRE_SERDE = mint(:pre_serde, 1300)
      # The serde pillar, reserved in the ordering with no shipped behaviour (PIPE-2).
      SERDE = mint(:serde, 1400, pillar: true)
      # After the serde pillar.
      POST_SERDE = mint(:post_serde, 1500)
      # The terminal transport hop (PIPE-8): flagged a pillar, holds no user step, and flattening
      # skips it.
      SEND = mint(:send, 1600, pillar: true, terminal: true)

      # The total ordering, ascending. Merely frozen, not Ractor.make_shareable'd: the port makes
      # no shareability claim for anything in the pipeline (plan open question 2).
      ALL = [
        PRE_REDIRECT, REDIRECT, POST_REDIRECT,
        PRE_RETRY, RETRY, POST_RETRY,
        PRE_AUTH, AUTH, POST_AUTH,
        PRE_LOGGING, LOGGING, POST_LOGGING,
        PRE_SERDE, SERDE, POST_SERDE,
        SEND,
      ].freeze

      # The five configurable pillars (PIPE-4), in precedence order, SEND excluded.
      PILLARS = [REDIRECT, RETRY, AUTH, LOGGING, SERDE].freeze

      LOOKUP = ALL.flat_map { |stage| [[stage.name, stage], [stage.name.to_s, stage]] }.to_h.freeze
      private_constant :LOOKUP

      # The only lookup (P4-32): the stage whose name is `name`, as a Symbol or a String.
      #
      # @param name [Symbol, String]
      # @return [Dexpace::Pipeline::Stage] the constant itself, by identity
      # @raise [Dexpace::InvalidArgumentError] for a name no stage carries
      def self.of(name)
        LOOKUP.fetch(name) do
          raise InvalidArgumentError, "unknown stage: #{name.inspect} (PIPE-1)"
        end
      end
    end
  end
end
