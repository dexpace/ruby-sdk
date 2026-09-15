# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A codec missing one method (#dump_into), so the conformance predicate has something to reject
# and Serde.missing_methods something to name.
class IncompleteCodec
  def media_type = "application/vnd.dexpace.incomplete"
  def dump_string(value) = value.to_s
  def dump_bytes(value) = value.to_s.b
  def dump_to(value, sink) = sink.write(dump_string(value))
  def load(source, witness) = witness.call(source.read)
end
