# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"
require_relative "outcomes"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 5, security by default and observability totality: XCUT-16, XCUT-19 and XCUT-20.
      # A private_constant of InvariantSuite.
      module Security
        extend self

        # One URL carrying every secret XCUT-19 names: userinfo, a query value and a fragment.
        SECRET_URL = "https://u:pw@h.example/p?token=s&page=2#k=v"

        # Each assertion below is one requirement's CLAUSES, and each clause is one Check, so the
        # metric is counting the requirement's own size. Splitting by count would split by
        # arithmetic rather than by behaviour -- which is .rubocop.yml's own recorded argument for
        # turning Minitest/MultipleAssertions off, applied to the assertions that mirror them.
        # rubocop:disable Metrics/AbcSize
        # XCUT-16: "a credential MUST NOT be stamped onto a request over a non-secure transport.
        # The auth layer MUST reject (fail loudly) BEFORE any token fetch or header write. The
        # guard applies ONLY on the credential-attaching path -- a deliberately credential-free
        # re-issue (a marker-suppressed cross-origin redirect) MAY proceed over any scheme."
        #
        # All three clauses, because a port can satisfy any two: the plaintext refusal, the HTTPS
        # stamp that proves the refusal is about the scheme and not about the path being broken,
        # and the marker-suppressed exception that proves the guard is not applied where no
        # credential is attached.
        def credentials_require_https(subject)
          subject.probe!(:Auth, "6c's authentication layer")
          refusal = Outcomes.raised_class(-> { subject.credential_hop(url: "http://a.example/x") })

          Check.that(refusal == subject.core::Auth.const_get(:HTTPSRequiredError),
                     "a credential was stamped over a plaintext transport, or the refusal was " \
                     "not the loud one the requirement names",
                     expected: "Auth::HTTPSRequiredError", actual: refusal, ids: ["XCUT-16"],)
          stamped = subject.credential_hop(url: "https://a.example/x")
          Check.that(!stamped.headers["authorization"].nil?,
                     "no credential was attached over HTTPS, so the plaintext refusal proves " \
                     "nothing about the scheme",
                     expected: "an Authorization header", actual: nil, ids: ["XCUT-16"],)
          suppressed = Outcomes.outcome_of(lambda {
            subject.credential_hop(url: "http://a.example/x", cross_origin: true)
          })
          Check.that(suppressed.respond_to?(:headers),
                     "a credential-FREE cross-origin re-issue was refused by the HTTPS guard, " \
                     "which applies only on the credential-attaching path",
                     expected: "a re-issued request", actual: suppressed.class, ids: ["XCUT-16"],)
          Check.that(suppressed.headers["authorization"].nil?,
                     "a marker-suppressed cross-origin re-issue carried a credential anyway",
                     expected: nil, actual: suppressed.headers["authorization"], ids: ["XCUT-16"],)
        end

        # XCUT-19, clauses (a), (b), (c) and (d): userinfo ALWAYS redacted and never allow-listed;
        # query values and key=value fragment tokens redacted unless allow-listed; header logging
        # default-deny; a credential object revealing no secret in string form. Clause (e), body
        # logging off by default, is HTTPLogging::DEFAULT's own.
        def redaction_is_default_deny(subject)
          subject.probe!(:Instrumentation, "5b's logging facade")
          redactor = subject.core::Instrumentation::Redactor::DEFAULT
          rendered = redactor.url(SECRET_URL)

          %w[pw token=s k=v].each do |leak|
            Check.that(!rendered.include?(leak), "#{leak.inspect} survived URL redaction",
                       expected: "redacted", actual: rendered, ids: ["XCUT-19"],)
          end
          Check.that(rendered.include?("h.example") && rendered.include?("/p"),
                     "host and path were redacted, which XCUT-19 does not ask",
                     expected: "preserved", actual: rendered, ids: ["XCUT-19"],)
          Check.that(!redactor.header_name?("authorization"),
                     "the header allow-list is not default-deny",
                     expected: false, actual: true, ids: ["XCUT-19"],)
          credential_reveals_nothing(subject)
        end

        # XCUT-20: "observability code paths MUST NEVER throw into the caller's request path. A
        # failure to redact/render/emit MUST degrade gracefully -- substitute a safe placeholder
        # such as a malformed-URL marker, or emit a self-describing instrumentation-error event --
        # and let the request proceed."
        #
        # Scoped exactly as 5c handed it forward: satisfied for what the SDK owns, and NOT
        # extended to a foreign tracer or meter callback, which OBS-20 deliberately carves out of
        # the containment. A `rescue` added around those is a guard this suite must not demand.
        def observability_never_throws(subject)
          subject.probe!(:Instrumentation, "5b's logging facade")
          redactor = subject.core::Instrumentation::Redactor::DEFAULT
          marker = redactor.url(Object.new)

          Check.that(marker.is_a?(::String),
                     "redacting a malformed URL threw into the caller's path instead of " \
                     "substituting a placeholder",
                     expected: "a String marker", actual: marker.class, ids: ["XCUT-20"],)
          Check.that(redactor.header_value("authorization", "Bearer x").is_a?(::String),
                     "a header value redaction returned something other than a String",
                     expected: "a String", actual: "other", ids: ["XCUT-20"],)
          contained = subject.core::Instrumentation.contain(
            subject.core::Instrumentation::Logger::NULL, event: "http.instrumentation.log",
          ) { raise "a sink exploded" }
          Check.that(contained.nil?,
                     "a failing log emission propagated into the caller's request path",
                     expected: nil, actual: contained, ids: ["XCUT-20"],)
          Check.that(subject.core::Instrumentation::Preview.render("\xFF\xFE".b, media_type: nil)
                            .is_a?(::String),
                     "rendering an undecodable body preview threw",
                     expected: "a String", actual: "raised", ids: ["XCUT-20"],)
        end

        # XCUT-19 (d): "credential objects MUST NOT reveal their secret in string/serialized
        # form." Three renderings, and the third is checked STRUCTURALLY: pp.rb gives a Data its
        # OWN #pretty_print over `members` and never consults an #inspect override, so a
        # credential that overrode only #to_s and #inspect still printed its token under `pp`.
        # The owner test rather than a rendered comparison, because this gem declares dexpace-core
        # and nothing else and `pp` is outside the require allowlist -- the rendered form is
        # asserted only where a consumer's process has already loaded it.
        def credential_reveals_nothing(subject)
          secret = "s3cr3t-value"
          token = subject.core::Auth::BearerToken.build(token: secret)
          rendered = [token.to_s, token.inspect]

          Check.that(rendered.none? { |text| text.include?(secret) },
                     "a credential revealed its secret in string or inspect form",
                     expected: "redacted in every rendering", actual: rendered.grep(/#{secret}/),
                     ids: ["XCUT-19"],)
          owner = token.class.method_defined?(:pretty_print) &&
                  token.class.instance_method(:pretty_print).owner
          Check.that(owner == token.class,
                     "a credential does not override #pretty_print, so `pp credential` prints " \
                     "its members -- pp.rb never consults an #inspect override on a Data",
                     expected: token.class, actual: owner, ids: ["XCUT-19"],)
        end

        # rubocop:enable Metrics/AbcSize

        ROWS = [
          ["XCUT-16", "a credential is never stamped over a non-HTTPS transport",
           :credentials_require_https,],
          ["XCUT-19", "logging redacts secrets by default", :redaction_is_default_deny],
          ["XCUT-20", "observability never throws into the caller's request path",
           :observability_never_throws,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Security
    end
  end
end
