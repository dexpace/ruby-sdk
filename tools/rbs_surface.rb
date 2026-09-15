# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "rbs"

# NFR-11, mechanised: no constant outside Dexpace:: and a fixed stdlib allowlist appears in any
# public signature under sig/.
#
# The scan works on PARSED and RESOLVED declarations rather than raw text. The paths are loaded
# together as one signature set and every type name in them is made absolute against that set
# -- the same resolution `rbs validate` performs -- so a relative `Headers` written inside
# `module Dexpace` is read as `::Dexpace::Headers`, a type variable is a variable and not a
# constant, and a comment mentioning Async::Task is not a leak. A name that resolves to nothing
# declared in the set stays exactly as written, which is what a foreign reference is. Each type
# tree is then walked constructor by constructor, so a leak is found in a tuple, a record, a
# proc, an optional or a type argument as surely as in a bare return type.
module RbsSurface
  extend self

  # Core Ruby and the stdlib names the allowlist in RequireAllowlist admits. `Data` is the base
  # of every core model (design §4), `ArgumentError` is the superclass HTTP-47 gives the
  # validation error (phase 1, P1-3) and `StringScanner` is `strscan`, which the require
  # allowlist admits; all three were added when the first real signatures needed them. Phase 3a
  # added `EOFError` and `IOError` -- the superclasses IO-16 and IO-4/IO-17/IO-42 give the two
  # stream failure types (P3-3), both core Ruby -- and `Encoding`, which IO-13's charset reads
  # take, for the same reason.
  STDLIB_ALLOWED = %w[
    ArgumentError Array Bool Class Comparable Data Encoding Enumerable Enumerator EOFError
    Exception Float Hash IO IOError Integer Method Module Mutex Numeric Object Proc Range
    Rational Regexp Set StandardError String StringIO StringScanner Symbol Thread Time URI
  ].freeze

  # The type constructors that carry a name. RBS::Types::Variable does not: `T` is a parameter.
  NAMED = [
    RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Alias,
    RBS::Types::Interface,
  ].freeze

  def violations(paths)
    resolved(paths.sort).flat_map { |source| foreign(source) }
  rescue RBS::BaseError => error
    # A set the scan cannot resolve is a set it cannot vouch for. rbs:validate runs first and
    # names the defect in full; this line keeps the gate red rather than green by accident.
    ["public signatures could not be resolved as one set, so NFR-11 is unchecked: " \
     "#{error.class.name.split("::").last}: #{error.message}"]
  end

  private

  def foreign(source)
    found = []
    collect(source.declarations, found)
    found.map { |name| name.to_s.delete_prefix("::") }.uniq.reject { |name| permitted?(name) }
      .map { |name| message(source.buffer.name, name) }
  end

  def message(path, name)
    "#{path}: public signature references #{name}, which is outside Dexpace:: and the " \
      "stdlib allowlist (NFR-11)."
  end

  # Dexpace itself and anything under it; a namespace that merely starts with the letters
  # (`DexpaceX::Thing`) is as foreign as `Async::Task`.
  def permitted?(name)
    name == "Dexpace" || name.start_with?("Dexpace::") ||
      STDLIB_ALLOWED.include?(name.split("::").first)
  end

  def resolved(paths)
    environment = RBS::Environment.new
    paths.each do |path|
      buffer = RBS::Buffer.new(name: path, content: File.read(path))
      environment.add_source(RBS::Source::RBS.new(*RBS::Parser.parse_signature(buffer)))
    end
    environment.resolve_type_names.each_rbs_source
  end

  # Every position a type name can occupy in a signature, not just a method's return type.
  def collect(node, found)
    case node
    when Array then node.each { |child| collect(child, found) }
    when RBS::AST::Declarations::Base then collect_declaration(node, found)
    when RBS::AST::Members::Base then collect_member(node, found)
    end
  end

  def collect_declaration(node, found)
    case node
    when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias
      # `class Runner = Async::Task` publishes the aliased constant under a Dexpace:: name --
      # the NFR-11 leak in its most direct form.
      found << node.old_name
    when RBS::AST::Declarations::TypeAlias, RBS::AST::Declarations::Constant,
         RBS::AST::Declarations::Global
      collect_params(node.type_params, found) if node.respond_to?(:type_params)
      collect_type(node.type, found)
    else # a class, module or interface: what it applies, its generic bounds, then its members
      applied(node).each { |reference| collect_applied(reference, found) }
      collect_params(node.type_params, found)
      collect(node.members, found)
    end
  end

  def collect_member(node, found)
    case node
    when RBS::AST::Members::MethodDefinition
      node.overloads.each { |overload| collect_method_type(overload.method_type, found) }
    when RBS::AST::Members::Mixin then collect_applied(node, found)
    when RBS::AST::Members::Attribute, RBS::AST::Members::Var then collect_type(node.type, found)
    end
  end

  # A class's superclass and a module's self-types; an interface has neither.
  def applied(node)
    references = []
    references << node.super_class if node.respond_to?(:super_class)
    references.concat(node.self_types) if node.respond_to?(:self_types)
    references.compact
  end

  # A superclass, self-type or mixin is a name applied to arguments (`Foo[Bar]`), and
  # `include Wrapper[Async::Task]` leaks exactly what `include Async::Task` does.
  def collect_applied(node, found)
    found << node.name
    node.args.each { |arg| collect_type(arg, found) }
  end

  # Generic bounds and defaults: `class Box[T < Async::Task]`, `[U = Async::Task]`.
  def collect_params(params, found)
    params.each do |param|
      param.map_type do |type|
        collect_type(type, found)
        type
      end
    end
  end

  # A method's own type parameters, then every type in its parameters, return, block and
  # self-type bindings.
  def collect_method_type(method_type, found)
    collect_params(method_type.type_params, found)
    method_type.each_type { |type| collect_type(type, found) }
  end

  def collect_type(type, found)
    found << type.name if NAMED.any? { |named| type.is_a?(named) }
    type.each_type { |child| collect_type(child, found) }
  end
end
