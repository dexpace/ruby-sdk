# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A codec that implements the seam and nothing beyond it. It is not a JSON codec and does not
# pretend to be: SEAM-19's point is that a codec declares its own media type, so the fake declares
# an obviously fake one and the test asserts the seam never defaults it.
class FakeCodec
  def media_type = "application/vnd.dexpace.fake"

  def dump_string(value) = value.to_s

  def dump_bytes(value) = value.to_s.b

  # SEAM-20: a streaming variant never closes the caller's target.
  def dump_to(value, sink) = sink.write(dump_string(value))

  def dump_into(value, buffer, offset:)
    encoded = dump_string(value)
    raise ::IndexError, "buffer too small" if offset + encoded.bytesize > buffer.bytesize

    buffer[offset, encoded.bytesize] = encoded
    encoded.bytesize
  end

  # SEAM-21: reads to EOF, never closes the caller's source, and requires an explicit witness --
  # there is no witness-less overload to fall into (SEAM-22's surviving clause).
  def load(source, witness) = witness.call(source.read)
end
