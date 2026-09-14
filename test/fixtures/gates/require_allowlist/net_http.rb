# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture. Stable default gem, denied to EVERY gem: only a transport adapter reaches the
# wire, and it does so through the one gem its gemspec declares, never by this name alone.
require "net/http"
