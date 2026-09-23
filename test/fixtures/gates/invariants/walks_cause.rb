# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A .cause in a comment and in a string, which a grep reports and the AST does not.
module Walks
  def self.a(error) = error.cause                    # :CALL
  def self.b(error) = error&.cause                   # :QCALL
  def self.c(errors) = errors.map(&:cause)           # :BLOCK_PASS
  def self.d(logger, error) = logger.event(:warn).cause(error).emit # carries an argument
  def self.s = "error.cause in a string"

  class Chained < ::StandardError
    def bare = cause                                 # :VCALL
    def parens = cause()                             # :FCALL
  end
end
