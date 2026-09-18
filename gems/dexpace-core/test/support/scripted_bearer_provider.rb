# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# A synchronous bearer provider (#fetch only, AUTH-11's commonest shape) answering a SCRIPT,
# one item per fetch: a BearerToken is returned, an Exception is raised, a callable is called
# and its result returned, and a bare String becomes a never-expiring token of that value.
# The script's LAST item repeats once the script is exhausted, so a provider built with one
# token answers it forever. Counts fetches under a mutex, which is how AUTH-34's "at most one
# provider fetch" is asserted from sixteen threads.
class ScriptedBearerProvider
  attr_reader :fetches

  def initialize(*script)
    raise ArgumentError, "a script needs at least one item" if script.empty?

    @script = script
    @fetches = 0
    @mutex = ::Thread::Mutex.new
    @before_fetch = nil
  end

  # A callable run inside every #fetch, BEFORE the scripted reply -- how a test parks the
  # fetch on a barrier to make a race deterministic.
  def before_fetch(&block)
    @before_fetch = block
    self
  end

  def fetch
    item = @mutex.synchronize do
      @fetches += 1
      @script.size > 1 ? @script.shift : @script.first
    end
    @before_fetch&.call
    raise item if item.is_a?(Exception)

    item = item.call if item.respond_to?(:call)
    item.is_a?(String) ? Dexpace::Auth::BearerToken.build(token: item) : item
  end
end
