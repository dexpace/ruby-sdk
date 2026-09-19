# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# A recording stand-in for AsyncBearerStamper whose three methods can be told apart on the
# wire: #stamp writes "Bearer cached", #stamp_fresh writes "Bearer fresh", and
# #evict_if_matches answers the Boolean it was built with, every call recorded in order. The
# real stamper cannot distinguish the two stamps after a successful eviction -- its cache is
# empty either way, so both await a fetch -- which is why AUTH-37's post-eviction routing
# ("#stamp_fresh after an eviction, #stamp after a preserved token") is asserted through this
# double and not through it (review round 0's R0-1). Both stamps return an already-settled
# future, the shape a #stamp-answering stamper hands AsyncStep.
class SpyBearerStamper
  attr_reader :calls

  def initialize(evicts:)
    @evicts = evicts
    @calls = []
  end

  def stamp(request)
    @calls << :stamp
    settled(stamped(request, "Bearer cached"))
  end

  def stamp_fresh(request)
    @calls << :stamp_fresh
    settled(stamped(request, "Bearer fresh"))
  end

  def evict_if_matches(rejected_header)
    @calls << [:evict_if_matches, rejected_header]
    @evicts
  end

  private

  def stamped(request, value)
    request.with(headers: request.headers.new_builder.set("Authorization", value).build)
  end

  def settled(request)
    completer = Dexpace::Async::Completer.new
    completer.fulfil(request)
    completer.future
  end
end
