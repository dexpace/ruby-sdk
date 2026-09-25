# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture. A `dexpace/` prefix that climbs back out of the namespace: `dexpace/../json` is
# `json` to Kernel#require, and a prefix test reads it as the gem's own path (phase 0's R3-2).
require "dexpace/../json"
require "dexpace/./../base64"
