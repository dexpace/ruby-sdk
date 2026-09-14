# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# NFR-4's runtime surface snapshot. Walks a namespace's constant tree and renders one line per
# entry, sorted, so a diff against the committed manifest names exactly what moved:
#
#   Dexpace::Foo                   a module or class
#   Dexpace::Foo#call              a public instance method, defined on it
#   Dexpace::Foo.build             a public singleton method -- a factory a caller reaches
#   Dexpace::Foo::LIMIT : Integer  a non-module constant, with its class
#
# One line per method rather than one per module, so that a manifest is a set: the lines a gem
# contributes to a tree another gem also populates are then exactly the lines that gem lacks
# (#contribution), and a drift message names the one method that moved.
#
# Design §4 builds every model as `class X < Data.define(...)`, and Ruby defines the generated
# readers on the anonymous class Data.define returns -- X's superclass -- not on X. That
# superclass is walked with X, because those readers ARE X's public surface and this gate exists
# to catch exactly the members RBS cannot see. Data's own `with`, `to_h` and friends live one
# level further up, on Data itself, and are Ruby's surface rather than this repository's.
module Surface
  extend self

  def manifest(root_constant)
    lines = []
    walk(Object.const_get(root_constant), root_constant, lines)
    lines.sort.join("\n") << "\n"
  end

  # The lines the block adds to `root_constant`'s manifest, measured around the block in the
  # process that runs it. This is an adapter's manifest: the walk starts at `Dexpace`, the root
  # of the tree, and not at the adapter's own constant, because an entry file can define beside
  # its namespace -- `Dexpace::Transport::Shared`, a method on `Dexpace::Transport`, a constant
  # directly under `Dexpace` -- as easily as inside it, and only the root sees both. Core's own
  # lines, loaded before the block, are subtracted, so an adapter's manifest holds what that
  # gem publishes and a change to core regenerates one manifest rather than six. A root that is
  # not yet defined contributes nothing to `before`, which is core's own case.
  def contribution(root_constant)
    before = Object.const_defined?(root_constant) ? manifest(root_constant).lines : []
    yield
    (manifest(root_constant).lines - before).join
  end

  private

  def walk(mod, root, lines)
    lines << mod.name
    lines.concat(method_lines(mod))

    mod.constants(false).sort.each do |name|
      value = mod.const_get(name)
      if value.is_a?(Module) && value.name.to_s.start_with?("#{root}::")
        walk(value, root, lines)
      else
        lines << "#{mod.name}::#{name} : #{value.class}"
      end
    end
  end

  def method_lines(mod)
    instance = (mod.public_instance_methods(false) + data_readers(mod)).uniq
    singleton = mod.singleton_class.public_instance_methods(false)
    instance.map { |name| "#{mod.name}##{name}" } + singleton.map { |name| "#{mod.name}.#{name}" }
  end

  # The readers on the anonymous Data.define return value a model subclasses; [] otherwise.
  # Only the ones still public on the model itself: a model that hides a member with
  # `private :values` makes the reader private on its own class while the superclass's copy
  # stays public, and the surface is what a caller can reach, which `public_method_defined?`
  # answers from the model's point of view (phase 1's Headers and Query do exactly this).
  def data_readers(mod)
    return [] unless mod.is_a?(Class) && anonymous_data?(mod.superclass)

    mod.superclass.public_instance_methods(false).select { |name| mod.public_method_defined?(name) }
  end

  def anonymous_data?(klass)
    !klass.nil? && klass.name.nil? && klass < Data
  end
end
