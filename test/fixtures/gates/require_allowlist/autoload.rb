# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture. Module#autoload registers a deferred require of its second argument, and the feature is audited as that require.
module Dexpace
  autoload :JSON, "json"
end
