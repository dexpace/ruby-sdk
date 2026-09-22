# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "prism"
require_relative "versions"

# SEAM-1's dependency audit. Ruby has no compile-versus-runtime dependency scope, so an empty
# runtime_dependencies list for core is not evidence of the invariant -- it IS the invariant.
module GemspecAudit
  extend self

  CORE = "dexpace-core"

  # The calls that start a subprocess, beside the backtick and %x literals the parser names.
  SUBPROCESS_CALLS = %i[system spawn exec popen popen2 popen2e popen3 capture2 capture2e capture3]
    .freeze

  def violations(root)
    versions_path = File.join(root, "VERSIONS")
    expected_constraint = constraint_for(versions_path)

    Dir.glob(File.join(root, "gems/*/*.gemspec")).flat_map do |path|
      spec = Gem::Specification.load(path)
      # A gemspec that raises while evaluating loads as nil (RubyGems warns and carries on), and
      # the finding should name the file rather than surface as a NoMethodError on nil.
      next ["#{path}: gemspec did not load."] if spec.nil?

      # NFR-10's floor is per gem since phase 8c (P8-36): a gem with a `floor:<gem>` row in
      # VERSIONS declares that one, every other gem the global one.
      gem_name = File.basename(path, ".gemspec")
      expected_floor = ">= #{DexpaceVersions.ruby_floor(gem_name, versions_path)}"
      check(spec, expected_constraint, expected_floor)
    end
  end

  private

  def constraint_for(versions_path)
    major, minor, = DexpaceVersions.value("gem", CORE, versions_path).split(".")
    "~> #{major}.#{minor}"
  end

  def check(spec, expected_constraint, expected_floor)
    found = []
    found.concat(dependency_violations(spec, expected_constraint))
    unless spec.required_ruby_version.to_s == expected_floor
      found << "#{spec.name}: required_ruby_version is #{spec.required_ruby_version}, " \
               "expected #{expected_floor} (NFR-10)."
    end
    found.concat(files_violations(spec))
  end

  # NFR-12's ordering half. RubyGems sorts `spec.files` in its own reader (Specification#files,
  # on every Ruby in the matrix), so sortedness is not a property a gemspec can lose; what it can
  # lose is independence from git, and the design's assertion is that the list comes from a
  # `Dir.glob` and never from `git ls-files`, which lists nothing in a .gem built from a source
  # export. The gemspec is parsed and refused if it runs any subprocess at all -- a backtick, a
  # `%x`, or a `system`/`spawn`/`popen`/`capture*` call -- because the same argument reaches a
  # version read from `git describe`. Every file the gemspec `require_relative`s is parsed the
  # same way, transitively: the six gemspecs already load ../../tools/versions that way, and a
  # helper that shells out on the gemspec's behalf keeps the gemspec's own text clean.
  def files_violations(spec)
    offender = shelling_file(spec.loaded_from)
    return [] if offender.nil?

    where = offender == spec.loaded_from ? "the gemspec" : "#{offender}, loaded by the gemspec,"
    ["#{spec.name}: #{where} runs a subprocess; spec.files comes from a sorted Dir.glob so " \
     "that entry ordering depends on the inputs and not on git (NFR-12)."]
  end

  # The first file, starting at the gemspec and following require_relative, that runs a
  # subprocess; nil when none does. A target that does not exist is left to the gemspec load,
  # which has already failed on it.
  def shelling_file(path, seen = [])
    return nil if seen.include?(path) || !File.file?(path)

    seen << path
    root = Prism.parse_file(path).value
    return path if shells_out?(root)

    relative_targets(root, File.dirname(path)).each do |target|
      offender = shelling_file(target, seen)
      return offender unless offender.nil?
    end
    nil
  end

  def shells_out?(node)
    return true if node.is_a?(Prism::XStringNode) || node.is_a?(Prism::InterpolatedXStringNode)
    return true if node.is_a?(Prism::CallNode) && SUBPROCESS_CALLS.include?(node.name)

    node.compact_child_nodes.any? { |child| shells_out?(child) }
  end

  def relative_targets(node, dir, found = [])
    target = relative_target(node, dir)
    found << target unless target.nil?
    node.compact_child_nodes.each { |child| relative_targets(child, dir, found) }
    found
  end

  # The file a `require_relative "x"` call names, resolved the way Ruby resolves it; nil for
  # any other node, and for an argument that is not a literal.
  def relative_target(node, dir)
    return nil unless node.is_a?(Prism::CallNode) && node.name == :require_relative

    literal = node.arguments&.arguments&.first
    return nil unless literal.is_a?(Prism::StringNode)

    target = File.expand_path(literal.unescaped, dir)
    target.end_with?(".rb") ? target : "#{target}.rb"
  end

  def dependency_violations(spec, expected_constraint)
    names = spec.runtime_dependencies.map(&:name).sort
    return core_violations(spec, names) if spec.name == CORE

    adapter_violations(spec, names, expected_constraint)
  end

  def core_violations(spec, names)
    return [] if names.empty?

    ["#{spec.name} declares #{names.length} runtime dependency/dependencies " \
     "(#{names.join(", ")}); SEAM-1 and NFR-1 require zero."]
  end

  def adapter_violations(spec, names, expected_constraint)
    budget_violations(spec, names) + constraint_violations(spec, expected_constraint)
  end

  def budget_violations(spec, names)
    found = []
    found << "#{spec.name} does not depend on #{CORE}." unless names.include?(CORE)
    third_party = names - [CORE]
    if third_party.length > 1
      found << "#{spec.name} declares #{third_party.join(", ")}; NFR-2 allows core plus at most " \
               "one third-party library."
    end
    found
  end

  # The static half of design §2.3's version-skew guard: the runtime half is the registration-time
  # assertion phase 2 built on Dexpace::Registry#register.
  def constraint_violations(spec, expected_constraint)
    core = spec.runtime_dependencies.find { |dep| dep.name == CORE }
    return [] if core.nil? || core.requirement.to_s == expected_constraint

    ["#{spec.name} constrains #{CORE} as #{core.requirement}, expected " \
     "#{expected_constraint} from VERSIONS (design §2.3)."]
  end
end
