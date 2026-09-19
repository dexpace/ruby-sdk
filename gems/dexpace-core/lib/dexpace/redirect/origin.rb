# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Redirect
    # REDIR-8's origin tuple, compared against the SEED request's and never the previous
    # hop's: `[scheme, host, effective port]` with the scheme and host folded by a bare
    # `downcase` (HTTP-13's no-argument fold; the Dexpace/NoLocaleCaseFold cop is what makes
    # it a rule) and the port read off the parsed URI, which supplies the scheme default when
    # none was written (verified fact 3). An explicitly constructed triple rather than
    # `URI#==`, as design §6.2 specifies, so the default-port normalisation is visible.
    #
    # `to_s` on the scheme and host makes the triple total over a seed URL that has neither
    # (a request built over an opaque URI): the empty host matches no dispatchable target, so
    # every redirect off such a seed reads as cross-origin -- the direction that strips.
    #
    # A private_constant, asserted at Step's call sites, with a sig/ mirror because the strict
    # `core` Steep target types every file under lib/.
    module Origin
      extend self

      # @param uri [URI::Generic] absolute
      # @return [Array(String, String, Integer)]
      def of(uri)
        [uri.scheme.to_s.downcase, uri.host.to_s.downcase, uri.port]
      end

      # @param seed [Array(String, String, Integer)] Origin.of(seed_request.url), computed once
      #   per operation and threaded through the whole hop loop
      # @param target [URI::Generic] the resolved redirect target, or the current hop's URL
      # @return [Boolean] true iff the two origins differ in any component
      def cross?(seed, target)
        seed != of(target)
      end
    end
    private_constant :Origin
  end
end
