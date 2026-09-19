# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/step"
require_relative "../../../lib/dexpace/redirect/step"
require_relative "../../../lib/dexpace/auth/key_stamper"
require_relative "../../../lib/dexpace/auth/key_credential"
require_relative "../../support/auth_fixtures"

# Exercises: REDIR-11, REDIR-7, REDIR-8, AUTH-29 -- the phase-6 charter's convergence point 1:
# the end-to-end cross-origin credential-leak test with the REAL redirect step in front of the
# real AUTH step. Written by phase 6c, guarded with a skip because Dexpace::Redirect::Step did
# not exist on 6c's base, and un-guarded by phase 6b, which landed last and owns it (the 6b
# checklist's convergence-point row): the guard is gone, the step is built through
# Redirect::Step.build (6b's .new is private), and before the real step was installed the body
# was run red against a stub REDIRECT step that forked without the marker -- it failed on
# `authorization` reaching the foreign origin, the leak this test exists to catch.
class DexpaceAuthCrossOriginConvergenceTest < DexpaceTestCase
  include AuthFixtures

  ORIGIN = "https://api.example.test/v1/pets"
  FOREIGN = "https://evil.example.net/collect"

  def seed_request
    Dexpace::Request.build(method: "GET", url: ORIGIN, headers: Dexpace::Headers::EMPTY)
  end

  # A 302 to a foreign origin, then a 200 from it: whatever the second hop carries is what the
  # redirect layer let through.
  def two_hop_cross_origin_transport
    redirect = Dexpace::Response.builder
    redirect.request = seed_request
    redirect.protocol = Dexpace::Protocol::HTTP_1_1
    redirect.status = 302
    redirect.headers = Dexpace::Headers.inbound_builder.add("Location", FOREIGN).build
    @transport = SequencedTransport.new(redirect.build, ok)
  end

  def captured_headers_for_second_hop
    second = @transport.requests.fetch(1)
    [second.url.to_s, second.headers.names]
  end

  test "no Authorization header reaches a foreign origin after a redirect" do
    pipeline = Dexpace::Pipeline.builder(transport: two_hop_cross_origin_transport)
      .append(Dexpace::Redirect::Step.build, stage: STAGES::REDIRECT)
      .append(Dexpace::Auth::Step.build(
                stamper: Dexpace::Auth::KeyStamper.new(
                  Dexpace::Auth::KeyCredential.new(api_key: "secret"),
                ),
              ))
      .build
    response = pipeline.call(seed_request)
    url, names = captured_headers_for_second_hop

    assert_equal(200, response.status.code)
    assert_equal(FOREIGN, url)
    refute_includes(names.map { |name| name.to_s.downcase }, "authorization")
    # The seed hop was stamped: the suppression is per hop, not a missing stamper.
    assert_equal(["secret"], @transport.requests.first.headers["Authorization"])
  end
end
