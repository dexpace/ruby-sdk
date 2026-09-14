# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture, positive control: a comment naming a denied feature is not a require.
# A parsed scan reads call nodes; a pattern matched anywhere in a line would refuse this file.
# require "json"
module Dexpace
end
