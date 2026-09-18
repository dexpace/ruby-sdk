# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/keys"

# Exercises: OBS-4, OBS-20, OBS-39
#
# The vocabulary OBS-39 requires to be "stable and predictable", as frozen String constants --
# and, per §8.1, covered by the surface snapshot (test/fixtures/surface/dexpace-core.txt carries
# one row per constant), which is what makes the stability mechanised rather than promised.
class DexpaceInstrumentationKeysTest < DexpaceTestCase
  Keys = Dexpace::Instrumentation::Keys
  Events = Dexpace::Instrumentation::Events

  EXPECTED_KEYS = {
    EVENT: "event",
    HTTP_REQUEST_METHOD: "http.request.method",
    URL_FULL: "url.full",
    HTTP_RESPONSE_STATUS_CODE: "http.response.status_code",
    HTTP_RESPONSE_DURATION_MS: "http.response.duration_ms",
    HTTP_REQUEST_BODY_SIZE: "http.request.body.size",
    HTTP_RESPONSE_BODY_SIZE: "http.response.body.size",
    HTTP_REQUEST_BODY_PREVIEW: "http.request.body.preview",
    HTTP_RESPONSE_BODY_PREVIEW: "http.response.body.preview",
    HTTP_REQUEST_HEADER_PREFIX: "http.request.header.",
    HTTP_RESPONSE_HEADER_PREFIX: "http.response.header.",
    ERROR_TYPE: "error.type",
    CAUSE: "cause",
    MESSAGE: "message",
    INSTRUMENT_REQUEST_COUNT: "http.client.request.count",
    INSTRUMENT_REQUEST_DURATION: "http.client.request.duration",
  }.freeze

  EXPECTED_EVENTS = {
    HTTP_REQUEST: "http.request",
    HTTP_RESPONSE: "http.response",
    INSTRUMENTATION_PREFIX: "http.instrumentation.",
    INSTRUMENTATION_LOG: "http.instrumentation.log",
    INSTRUMENTATION_CLOSE: "http.instrumentation.close",
    INSTRUMENTATION_HOOK: "http.instrumentation.hook",
    INSTRUMENTATION_SHUTDOWN: "http.instrumentation.shutdown",
    INSTRUMENTATION_CONFIG: "http.instrumentation.config",
    # Phase 6c's, AUTH-37's log-and-continue: an auth-layer diagnostic, outside the prefix.
    AUTH_REFRESH: "http.auth.refresh",
  }.freeze

  # Sixteen: OBS-39's named minimum plus the reserved `event` key (OBS-4), the `cause` the
  # failure event attaches, the `message` the config diagnostic carries, and the two instrument
  # names R11 moved here from 5c. The exact set is asserted so a seventeenth cannot arrive
  # unnoticed: OBS-39 makes the vocabulary a contract.
  test "OBS-39: Keys holds exactly these sixteen frozen String constants" do
    assert_equal(EXPECTED_KEYS.keys.sort, Keys.constants.sort)
    EXPECTED_KEYS.each do |name, value|
      constant = Keys.const_get(name)

      assert_equal(value, constant, name.to_s)
      assert_predicate(constant, :frozen?, name.to_s)
    end
  end

  test "OBS-39, OBS-20: Events holds exactly these nine, six under the instrumentation prefix" do
    assert_equal(EXPECTED_EVENTS.keys.sort, Events.constants.sort)
    EXPECTED_EVENTS.each do |name, value|
      constant = Events.const_get(name)

      assert_equal(value, constant, name.to_s)
      assert_predicate(constant, :frozen?, name.to_s)
    end
    diagnostics = Events.constants.grep(/\AINSTRUMENTATION_/) - [:INSTRUMENTATION_PREFIX]

    assert_equal(5, diagnostics.size)
    diagnostics.each do |name|
      assert_operator(Events.const_get(name), :start_with?, Events::INSTRUMENTATION_PREFIX)
    end
  end

  # The header prefixes are what Event#field's reserved-key table matches (OBS-16, OBS-17), so
  # each must end in the dot that separates the prefix from the folded header name.
  test "OBS-39: the two header prefixes end in a dot and are distinct" do
    assert(Keys::HTTP_REQUEST_HEADER_PREFIX.end_with?("."))
    assert(Keys::HTTP_RESPONSE_HEADER_PREFIX.end_with?("."))
    refute_equal(Keys::HTTP_REQUEST_HEADER_PREFIX, Keys::HTTP_RESPONSE_HEADER_PREFIX)
  end
end
