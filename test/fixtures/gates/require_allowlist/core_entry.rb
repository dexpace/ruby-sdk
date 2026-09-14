# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture. The positive control for an adapter: core's own entry point, required by the
# name `dexpace` and not by a `dexpace/` path, which every adapter's gemspec already declares.
require "dexpace"
