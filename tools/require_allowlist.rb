# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "bundler"
require_relative "require_scan"

# Design §9.2, extended to every gem. A static scan of the source rather than a runtime trace,
# which is what lib/dexpace.rb's explicit requires buy. The scan itself -- parsed call nodes, so
# `require("json")`, `Kernel.require "json"` and `autoload :JSON, "json"` are all seen -- is
# RequireScan; this module is the policy applied to what it finds, and it refuses a feature the
# scan could not read, because a require the allowlist cannot see is a require it cannot vouch
# for.
#
# The Ruby 4.0.6 bundled-gem facts this list was built against are recorded once, in
# docs/knowledge/notes/package-and-dependency-layout.md, key
# `package-and-dependency-layout/70fbcaee`. They are not restated here: a second copy of a table
# that moves between releases is a second copy that goes stale silently. The category assertion
# in test/gates/require_allowlist_test.rb re-derives them from the running interpreter on every
# CI row instead.
module RequireAllowlist
  extend self

  # Deliberately narrower than "everything stable". The category is not the constraint; what core
  # actually needs is. Growing this list is a reviewed one-line diff naming the requirement that
  # motivated it. Every name was verified to require cleanly on 3.2.11, 3.4.10 and 4.0.6.
  ALLOWED = %w[
    date
    digest
    forwardable
    monitor
    openssl
    securerandom
    set
    singleton
    stringio
    strscan
    time
    uri
  ].freeze

  # A denial: the reason, and the gems it binds. `scope: nil` is every gem, which is the default
  # and the strict direction -- widening is a reviewed edit, narrowing is never accidental.
  # `scope:` holds gem-name globs (`File.fnmatch`), because a reason written for core ("core
  # embeds no concrete transport") does not describe dexpace-conformance, whose wire server is a
  # socket by definition.
  Denial = Data.define(:reason, :scope) do
    def binds?(gem)
      return true if scope.nil? || gem.nil?

      scope.any? { |pattern| File.fnmatch(pattern, gem) }
    end
  end

  NO_TRANSPORT_REASON = "SEAM-1/SEAM-2: core embeds no concrete transport, and a transport " \
                        "adapter reaches the wire only through the one gem it declares."

  # A scoped-out denial is an implicit permission for every gem outside the scope, so a scope
  # is exactly as wide as the case that argued for it. The case argued (the Task 9 amendment,
  # phase 8a's P8-14) is dexpace-conformance requiring `socket`, whose wire server is a socket
  # by definition; nothing argued for net/http, net/protocol, open-uri or resolv anywhere but a
  # transport adapter, which reaches them through the one gem it declares, so those four stay
  # denied to every gem.
  NO_TRANSPORT = Denial.new(reason: NO_TRANSPORT_REASON, scope: nil)
  NO_SOCKET = Denial.new(reason: NO_TRANSPORT_REASON, scope: %w[dexpace-core dexpace-transport-*])

  # Names that pass a category test and must still fail. Without this list the gate's message
  # would be "not in the allowlist", which says nothing about why.
  DENIED = {
    "json" => Denial.new(
      reason: "SEAM-2: the wire codec is a seam. It lives in dexpace-serde-json, and the " \
              ">= 2.19.9 floor lives in that gemspec and nowhere else (design §3.4).",
      scope: nil,
    ),
    "timeout" => Denial.new(
      reason: "Design §8.3: Timeout.timeout can land an interrupt inside an `ensure` " \
              "releasing a pooled connection. Deadlines are explicit values.",
      scope: nil,
    ),
    "socket" => NO_SOCKET,
    **%w[net/http net/protocol open-uri resolv].to_h { |name| [name, NO_TRANSPORT] },
  }.freeze

  def bundled? = defined?(Gem::BUNDLED_GEMS::SINCE) ? true : false
  def bundled_since = bundled? ? Gem::BUNDLED_GEMS::SINCE : {}

  def violations(root)
    Dir.glob(File.join(root, "gems/*")).flat_map do |gem_dir|
      gem = File.basename(gem_dir)
      permitted = third_party_for(gem_dir)
      lib_root = File.join(gem_dir, "lib")
      Dir.glob(File.join(lib_root, "**/*.rb")).flat_map do |file|
        scan_file(file, permitted: permitted, lib_root: lib_root, gem: gem)
      end
    end
  end

  # Both forms are scanned, as design §9.2 and CLAUDE.md both say. `require` can reach outside
  # the gem by name; `require_relative` can reach outside it by path, which is the cross-gem
  # reach styleguide 12.6 forbids and which would make the gem unbuildable once packaged.
  # `gem:` names the gem being scanned so a scoped denial can be consulted; nil is strict.
  def scan_file(path, permitted:, lib_root:, gem: nil)
    RequireScan.calls(path).filter_map do |call|
      verdict(call, path, lib_root) { |name| reason_for(name, permitted, gem) }
    end
  rescue RequireScan::ParseError => error
    ["#{path}: #{error.message}, so the require audit cannot read it."]
  end

  private

  def verdict(call, path, lib_root)
    where = "#{path}:#{call.line}"
    return unreadable(where, call) if call.feature.nil?
    return check_relative(where, call.feature, path, lib_root) if call.verb == :require_relative

    reason = yield(call.feature)
    reason && "#{where}: #{call.verb} \"#{call.feature}\" -- #{reason}"
  end

  def unreadable(where, call)
    "#{where}: #{call.verb} #{call.arguments || "with no argument"} -- the feature is not a " \
      "string literal, so the allowlist cannot see it. Name the feature as a literal."
  end

  def check_relative(where, target, path, lib_root)
    resolved = File.expand_path(target, File.dirname(path))
    return nil if resolved.start_with?("#{File.expand_path(lib_root)}/")

    "#{where}: require_relative \"#{target}\" escapes #{lib_root}. A gem may not reach " \
      "outside its own lib/ (styleguide 12.6); the packaged gem would not contain it."
  end

  # nil means the require is fine. The order matters: a declared dependency or a dexpace/ path
  # is fine before anything else is asked; a denial that binds this gem wins over its category;
  # a bundled name is refused with its date; and only then is the allowlist consulted.
  def reason_for(name, permitted, gem)
    return nil if reachable?(name, permitted)

    denial = DENIED[name]
    return denial.reason if denial&.binds?(gem)

    since = bundled_since[name.split("/").first]
    return "bundled since #{since}; a gem must declare it explicitly under Bundler." if since
    return nil if ALLOWED.include?(name) || !denial.nil? # a scoped-out denial is reachable stdlib

    "not in the require allowlist. Add it to RequireAllowlist::ALLOWED with the requirement " \
      "that motivated it, or declare it as a dependency if this is an adapter (NFR-2)."
  end

  # A declared dependency, or a path inside the gem's own namespace -- including core's entry
  # point itself, which every adapter requires by the name `dexpace` and not `dexpace/...`.
  def reachable?(name, permitted)
    permitted.include?(name) || name == "dexpace" || name.start_with?("dexpace/")
  end

  # An adapter may require the one third-party gem its own gemspec declares. In phase 0 no
  # gemspec declares one, so this is empty for all six -- which is SEAM-1 restated at the require
  # level, and the reason the method exists now rather than in phase 7.
  def third_party_for(gem_dir)
    name = File.basename(gem_dir)
    spec = Gem::Specification.load(File.join(gem_dir, "#{name}.gemspec"))
    return [] if spec.nil?

    spec.runtime_dependencies.map(&:name).reject { |dep| dep == "dexpace-core" }
      .flat_map { |dep| [dep, dep.tr("-", "/")] }
  end
end
