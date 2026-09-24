# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Every shape that reaches #cause by NAME rather than by call syntax, plus the one that is
# statically undecidable and is the gate's stated gap.
module Bad
  def self.a(error) = error.cause
  def self.b(error) = error&.cause
  def self.c(error) = error.send(:cause)
  def self.d(error) = error.__send__(:cause)
  def self.e(error) = error.public_send(:cause)
  def self.f(error) = error.method(:cause).call
  def self.g(error) = error.send("cause")            # a String literal, caught the same way
  def self.h(error, name) = error.send(name)         # undecidable: the stated gap
end
