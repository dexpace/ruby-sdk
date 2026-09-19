# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# An AUTH-position probe for the redirect suite: 6b's half of the marker contract, observed
# from where 6c's real step reads it. Installed at Stages::AUTH (it declares no #stage, like
# every probe under test/support/, so the install names one), it records, per drive, the URL it
# was handed, whether the request STILL carried an Authorization header when it arrived -- which
# is what REDIR-7's "stripped before EVERY re-issue" means from inside the loop, since the AUTH
# position is downstream of the strip and upstream of the transport -- and whether the
# REDIRECT slot said cross-origin; then it stamps its own token unless suppressed, so the
# transport's view shows a per-hop re-stamp on a same-origin hop and nothing on a cross-origin
# one. The end-to-end proof with the real Auth::Step is cross_origin_convergence_test.rb.
class CredentialProbe
  attr_reader :decisions

  def initialize(token: "probe-token")
    @token = token
    @decisions = []
  end

  def call(request, cursor)
    suppressed = cursor.state(Dexpace::Pipeline::Stages::REDIRECT)[:cross_origin] ? true : false
    @decisions << { url: Dexpace::URL.external_form(request.url), suppressed: suppressed,
                    authorization: request.headers["Authorization"]&.first, }.freeze
    return cursor.call(request) if suppressed

    stamped = request.headers.new_builder.set("Authorization", "Bearer #{@token}").build
    cursor.call(request.with(headers: stamped))
  end
end
