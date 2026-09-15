# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"

require_relative "../model"

module Dexpace
  # URL parsing, pinned to one parser (design §3.5).
  #
  # ::URI::RFC3986_PARSER explicitly, never URI.parse and never URI::DEFAULT_PARSER: which parser
  # DEFAULT_PARSER names changed at exactly Ruby 3.4.0, which straddles this port's supported
  # range, so code written against it silently changes escaping and parsing behaviour across the
  # CI matrix without changing a line. A custom cop fails the build on either. RFC3986_PARSER has
  # been present since Ruby 3.0, so the pin costs nothing on the floor.
  #
  # A module of two functions, not a value type: the parsed URL is a URI::Generic, and wrapping
  # it would add a type every later phase has to unwrap.
  module URL
    extend self

    # The absolute URI the input denotes, parsed here and frozen through, or the HTTP-47 error
    # naming the input when it is malformed or relative.
    #
    # A URI object is re-parsed from its text rather than `dup`ed: URI::Generic#freeze is
    # shallow, `dup` shares the component Strings with the caller's object, and a String a caller
    # still holds is externally-mutable state XCUT-15 forbids a model from aliasing. Parsing
    # yields components this method owns, which it can then freeze without touching the caller's.
    def parse!(input)
      Model.required!("url", input)
      unless input.is_a?(String) || input.is_a?(::URI::Generic)
        raise InvalidArgumentError, "url must be a String or a URI, got #{input.class}"
      end

      # rbs's stdlib signatures declare URI::RFC3986_Parser as an empty class, so its #parse is
      # invisible to Steep; the annotation is local to this one call rather than a reopened
      # stdlib signature shipped in sig/, which would collide the day rbs fills the class in.
      parser = ::URI::RFC3986_PARSER #: untyped
      uri = parser.parse(input.to_s) #: URI::Generic
      unless uri.absolute?
        raise InvalidArgumentError, "url #{input.to_s.inspect} is not an absolute URI (HTTP-47)"
      end

      own(uri)
    rescue ::URI::InvalidURIError => error
      # The Task 1 rule: a stdlib exception raised because of the argument is re-raised as the
      # SDK's argument error, naming the input, with the original left as the cause.
      raise InvalidArgumentError, "url #{input.to_s.inspect} is malformed: #{error.message}"
    end

    # HTTP-46's comparison key. Ruby's URI performs no name resolution, so this is textual and
    # non-blocking by construction -- which the request equality test asserts rather than assumes.
    def external_form(uri)
      uri.to_s
    end

    private

    # Freezes the URI's String components, then the URI. Only Strings: a URI also references
    # its parser, a process-global object this method leaves alone -- the uri gem freezes
    # URI::RFC3986_PARSER at definition on every supported Ruby, so nothing here needs to touch
    # it -- which is why the result is frozen AND Ractor-shareable with no global frozen from
    # here (deviation P1-13; the request and response suites assert it).
    def own(uri)
      uri.instance_variables.each do |name|
        value = uri.instance_variable_get(name)
        value.freeze if value.is_a?(String)
      end
      uri.freeze
    end
  end
end
