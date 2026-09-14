# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture. A feature the scan cannot read: not a string literal, so the allowlist cannot vouch for it and refuses it rather than passing it.
feature = "json"
require feature
