# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# Exercises: REDIR-28, REDIR-15, OBS-39 -- the redirect layer's event and key vocabulary: five
# event names and four field keys, frozen Strings, distinct, under one `http.redirect.` prefix,
# with the two REDIR-15 outcomes as two names and the raw-Location key distinct from every
# URL-valued key the redactor sees. The emissions themselves are asserted in step_test.rb.
class DexpaceRedirectEventsTest < DexpaceTestCase
  Events = Dexpace::Redirect::Events
  Keys = Dexpace::Redirect::Keys

  EVENT_NAMES = %i[
    HOP_FOLLOWED LOOP_DETECTED SCHEME_DOWNGRADE_REJECTED SCHEME_DOWNGRADE_PERMITTED
    LOCATION_MALFORMED
  ].freeze
  KEY_NAMES = %i[FROM_URL TO_URL REDIRECT_COUNT LOCATION_RAW].freeze

  test "REDIR-28: exactly these five event names, frozen, distinct, under http.redirect." do
    assert_equal(EVENT_NAMES.sort, Events.constants.sort)
    values = EVENT_NAMES.map { |name| Events.const_get(name) }

    assert(values.all?(::String))
    assert(values.all?(&:frozen?))
    assert_equal(values.uniq, values)
    assert(values.all? { |value| value.start_with?("http.redirect.") })
  end

  test "REDIR-28: exactly these four field keys, frozen, distinct, under http.redirect." do
    assert_equal(KEY_NAMES.sort, Keys.constants.sort)
    values = KEY_NAMES.map { |name| Keys.const_get(name) }

    assert(values.all?(::String))
    assert(values.all?(&:frozen?))
    assert_equal(values.uniq, values)
    assert(values.all? { |value| value.start_with?("http.redirect.") })
  end

  test "REDIR-15: the permitted-downgrade event is a DIFFERENT name from the rejected one" do
    refute_equal(Events::SCHEME_DOWNGRADE_REJECTED, Events::SCHEME_DOWNGRADE_PERMITTED)
  end

  test "REDIR-28: no redirect key collides with a 5b key, and none is 5b's structurally " \
       "redacted url.full -- the redirect step redacts its URL fields by name, itself" do
    fivebs = Dexpace::Instrumentation::Keys.constants.map do |name|
      Dexpace::Instrumentation::Keys.const_get(name)
    end

    KEY_NAMES.each do |name|
      refute_includes(fivebs, Keys.const_get(name))
    end
    refute_equal(Dexpace::Instrumentation::Keys::URL_FULL, Keys::FROM_URL)
    refute_equal(Dexpace::Instrumentation::Keys::URL_FULL, Keys::TO_URL)
  end

  test "REDIR-28: the raw-Location key is distinct from every URL-valued key" do
    refute_equal(Keys::LOCATION_RAW, Keys::FROM_URL)
    refute_equal(Keys::LOCATION_RAW, Keys::TO_URL)
  end

  test "OBS-39: 5b's Events pin is untouched -- the redirect names live here, not there" do
    Events.constants.each do |name|
      refute(Dexpace::Instrumentation::Events.const_defined?(name, false), name.to_s)
    end
  end
end
