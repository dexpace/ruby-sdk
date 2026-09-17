# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "error/invalid_argument_error"

module Dexpace
  # The immutable proxy model (CFG-22): the protocol, the address as `host` and `port` -- two
  # members rather than one address type, because Ruby has no InetSocketAddress and URI::Generic
  # is not one, its #port defaulting to exactly what CFG-25 forbids (P5-5) -- an ordered list of
  # non-proxy host patterns, optional credentials, an optional challenge handler, and CFG-27's
  # explicit bypass-all flag, never a literal "*" in the list.
  #
  # BOTH string renderings mask the password (P5-7): Data's generated #inspect prints every
  # member, and #inspect -- not #to_s -- is what `p`, a log interpolation and an assert_equal
  # failure message print, so overriding only #to_s would satisfy CFG-22's letter and leak the
  # secret through the likeliest path. Phase 4a reached the opposite conclusion for a context
  # because a context holds no secret; here the secret is a member of the model.
  #
  # Ractor-shareable exactly when `challenge_handler` is nil (P5-6): a callable in a frozen Data
  # is not, and a claim that holds sometimes is not a claim.
  #
  # This file declares the class and is the ONLY entry point to it: proxy/type.rb,
  # proxy/host_pattern.rb and proxy/resolution.rb are required from inside its body, because the
  # first two reopen `class Proxy` with no superclass clause and loading either before this
  # declaration raises `TypeError: superclass mismatch`. None of the three appears in
  # lib/dexpace.rb.
  class Proxy < Data.define(
    :type, :host, :port, :non_proxy_hosts, :username, :password, :challenge_handler, :bypass_all,
  )
    include Model

    private_class_method :new

    # Validation lives here so #with, which routes through .build, meets it too.
    def initialize(type:, host:, port:, non_proxy_hosts:, username:, password:, challenge_handler:,
                   bypass_all:)
      super(
        type: Type.of(Model.required!("type", type)),
        host: host!(host),
        port: port!(port),
        non_proxy_hosts: patterns!(non_proxy_hosts),
        username: username.nil? ? nil : Model.frozen_string(username.to_s),
        password: password.nil? ? nil : Model.frozen_string(password.to_s),
        challenge_handler: challenge_handler,
        bypass_all: bypass_all ? true : false,
      )
    end

    # @param type [Type, String, Symbol] the protocol; resolved through Type.of
    # @param host [String] the proxy's host, non-blank
    # @param port [Integer] explicit and within 0..65535 (CFG-25); never defaulted
    # @param non_proxy_hosts [Array<HostPattern>] ordered, copied and frozen
    # @param username [String, nil] CFG-37's documented-nullable credential slot
    # @param password [String, nil] likewise
    # @param challenge_handler [Object, nil] likewise; opaque to core
    # @param bypass_all [Boolean] CFG-27's flag
    # @return [Proxy]
    # @raise [Dexpace::InvalidArgumentError] on an absent type, host or port, a blank host, a port
    #   outside 0..65535, or a non-proxy entry that is not a HostPattern
    def self.build(type:, host:, port:, non_proxy_hosts: [], username: nil, password: nil,
                   challenge_handler: nil, bypass_all: false)
      new(type: type, host: host, port: port, non_proxy_hosts: non_proxy_hosts, username: username,
          password: password, challenge_handler: challenge_handler, bypass_all: bypass_all,)
    end

    # CFG-23's bypass decision: true at once when bypass_all is set, otherwise true iff any
    # pattern matches the host.
    #
    # @param host [String] the request's target host
    # @return [Boolean]
    def bypass?(host)
      return true if bypass_all

      non_proxy_hosts.any? { |pattern| pattern.matches?(host) }
    end

    # `type://user:****@host:port`, the password masked and the username kept (CFG-22).
    #
    # @return [String]
    def to_s
      auth = username.nil? ? "" : "#{username}:****@"
      "#{type.name.downcase}://#{auth}#{host}:#{port}"
    end

    # Every member but the password, which prints as "****" when present and nil when absent;
    # the challenge handler prints as its class, never its contents.
    #
    # @return [String]
    def inspect
      "#<#{self.class.name} #{rendered_members.map { |name, value| "#{name}=#{value}" }.join(" ")}>"
    end

    # Resolves a proxy from configuration (CFG-24 through CFG-28) through the private resolver.
    # Never raises: invalid configuration yields nil and a Kernel#warn (P5-8).
    #
    # CFG-28's MAY is taken and its prohibition is met structurally: the argument defaults to
    # Dexpace.configuration, and NOTHING in core calls this. No environment read happens unless
    # a caller invokes the resolver, which is "nothing may read proxy configuration implicitly at
    # construction/startup" enforced by the absence of a call site rather than by a comment.
    #
    # @param configuration [Dexpace::Configuration] the chain to read; the process-wide slot by
    #   default
    # @return [Proxy, nil] nil when no proxy is configured, when the configuration is invalid
    #   (after a warning), or when the non-proxy list is bypass-all (CFG-27)
    # @raise [Dexpace::InvalidArgumentError] when handed something that is not a Configuration
    #   -- the one argument that is the caller's and not the configuration's
    def self.resolve(configuration = Dexpace.configuration)
      unless configuration.is_a?(Configuration)
        raise InvalidArgumentError,
              "configuration must be a Dexpace::Configuration, got #{configuration.class}"
      end

      ProxyResolution.resolve(configuration)
    end

    # The nested files reopen `class Proxy`, so they load HERE, inside the body the declaration
    # above created; proxy/resolution.rb is the private resolver behind .resolve.
    require_relative "proxy/type"
    require_relative "proxy/host_pattern"
    require_relative "proxy/resolution"

    private

    # #inspect's member list: the password masked to "****" when present, the handler named by
    # class only, the patterns by their globs, every value through #inspect.
    def rendered_members
      to_h.merge(
        type: type.name,
        password: password && "****",
        non_proxy_hosts: non_proxy_hosts.map(&:glob),
        challenge_handler: challenge_handler&.class&.name,
      ).transform_values(&:inspect)
    end

    def host!(host)
      text = Model.required!("host", host).to_s
      raise InvalidArgumentError, "host must not be blank" if text.strip.empty?

      Model.frozen_string(text)
    end

    # CFG-25's range check on the one member that carries it; the parser's own #port would have
    # defaulted an absent one to 80 by the time it was read, which is why the resolver never uses
    # it and why an absent port cannot reach here as anything but nil.
    def port!(port)
      Model.required!("port", port)
      unless port.is_a?(::Integer)
        raise InvalidArgumentError, "port must be an Integer, got #{port.class}"
      end
      unless (0..65_535).cover?(port)
        raise InvalidArgumentError, "port must be within 0..65535, got #{port}"
      end

      port
    end

    def patterns!(patterns)
      Model.required!("non_proxy_hosts", patterns)
      list = Array(patterns) #: Array[untyped]
      list.each do |entry|
        next if entry.is_a?(HostPattern)

        raise InvalidArgumentError,
              "non_proxy_hosts takes Proxy::HostPattern entries, got #{entry.class}"
      end
      Model.own(list)
    end
  end
end
