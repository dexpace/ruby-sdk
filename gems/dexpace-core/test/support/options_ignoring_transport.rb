# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A transport that ignores its options entirely, for SEAM-11's "a transport that ignores options
# MUST behave identically to the no-options call". Its own file, because Style/OneClassPerFile
# allows one top-level class per file.
class OptionsIgnoringTransport
  def initialize(response) = @response = response

  def call(_request, _options, _cancellation) = @response
end
