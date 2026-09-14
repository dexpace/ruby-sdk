# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture. A require_relative that resolves outside this directory, which stands in for a gem's lib/: the packaged gem would not contain it.
require_relative "../../../../Rakefile"
