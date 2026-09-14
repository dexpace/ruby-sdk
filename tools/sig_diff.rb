# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "open3"
require "rbs"

# NFR-4's signature half. Compares every public declaration under gems/*/sig against the
# previous release tag: a declaration present at the baseline and absent at HEAD is either a
# removal or a narrowing, and both are breaks.
#
# The comparison is over PARSED declarations, flattened to one line each (SigDiff::Surface), not
# over the lines of the file. A line-level comparison cannot see the two narrowings that leave
# every declaration line in place: an overload dropped from a method type written across
# continuation lines, and a public method moved under a `private` section -- and Ruby has no
# overloads for gates:surface_snapshot to catch the first from the runtime side.
#
# There is no baseline in a repository that has never been released, so this gate has a
# pre-release branch. That branch is reachable ONLY while no v* tag exists, and the gate asserts
# that rather than assuming it -- so the first tag arms the gate with no code change and nobody
# having to remember.
module SigDiff
  extend self

  # One line per public declaration, each carrying its full constant path, so a declaration is
  # compared as what it promises rather than as the text it was written in: reindenting a file,
  # reordering it, commenting it, or splitting a method type across overload lines reads the
  # same; dropping an overload or moving a method under `private` does not.
  class Surface
    KIND = { instance: "#", singleton: "." }.freeze

    def self.of(declarations)
      new.tap { |surface| surface.declarations(declarations, "") }.items.sort.uniq
    end

    attr_reader :items

    def initialize
      @items = []
    end

    def declarations(list, namespace)
      list.each { |node| declaration(node, namespace) }
    end

    private

    def declaration(node, namespace)
      node.respond_to?(:members) ? container(node, namespace) : leaf(node, namespace)
    end

    # A class, module or interface: its own header, then its members under its full name.
    def container(node, namespace)
      name = "#{namespace}#{node.name}"
      items << "#{verb(node)} #{name}#{params(node)}#{ancestry(node)}"
      members(node.members, name)
    end

    def leaf(node, namespace)
      case node
      when RBS::AST::Declarations::Constant then items << "#{namespace}#{node.name}: #{node.type}"
      when RBS::AST::Declarations::Global then items << "#{node.name}: #{node.type}"
      when RBS::AST::Declarations::TypeAlias then type_alias(node, namespace)
      when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias
        items << "#{verb(node)} #{namespace}#{node.new_name} = #{node.old_name}"
      end
    end

    def type_alias(node, namespace)
      items << "type #{namespace}#{node.name}#{params(node)} = #{node.type}"
    end

    def ancestry(node)
      return " < #{applied(node.super_class)}" if node.respond_to?(:super_class) && node.super_class
      return "" unless node.respond_to?(:self_types) && !node.self_types.empty?

      " : #{node.self_types.map { |type| applied(type) }.join(", ")}"
    end

    # A `private` line hides everything after it until `public`; `private def` hides one.
    def members(list, owner)
      section = :public
      list.each do |member|
        case member
        when RBS::AST::Members::Public then section = :public
        when RBS::AST::Members::Private then section = :private
        when RBS::AST::Declarations::Base then declaration(member, "#{owner}::")
        else member(member, owner, section)
        end
      end
    end

    def member(node, owner, section)
      return if hidden?(node, section)

      case node
      when RBS::AST::Members::MethodDefinition then method(node, owner)
      when RBS::AST::Members::Attribute then attribute(node, owner)
      when RBS::AST::Members::Mixin then items << "#{verb(node)} #{owner} #{applied(node)}"
      when RBS::AST::Members::Alias
        items << "alias #{owner}#{KIND.fetch(node.kind)}#{node.new_name} #{node.old_name}"
      end
    end

    # A member's own modifier (`private def`) wins over the section it sits in.
    def hidden?(node, section)
      own = node.respond_to?(:visibility) ? node.visibility : nil
      (own || section) == :private
    end

    # One line per overload, and one per receiver a `self?.` method answers to, so dropping
    # either half is a removal.
    def method(node, owner)
      receivers(node.kind).each do |separator|
        node.overloads.each do |overload|
          items << "def #{owner}#{separator}#{node.name}: #{overload.method_type}"
        end
        items << "def #{owner}#{separator}#{node.name}: ..." if node.overloading?
      end
    end

    def attribute(node, owner)
      receivers(node.kind).each do |separator|
        items << "#{verb(node)} #{owner}#{separator}#{node.name}: #{node.type}"
      end
    end

    def receivers(kind)
      kind == :singleton_instance ? KIND.values : [KIND.fetch(kind)]
    end

    # `AttrReader` -> `attr_reader`, `ClassAlias` -> `class_alias`, `Include` -> `include`.
    def verb(node)
      node.class.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    def params(node)
      node.type_params.empty? ? "" : "[#{node.type_params.join(", ")}]"
    end

    def applied(node)
      node.args.empty? ? node.name.to_s : "#{node.name}[#{node.args.join(", ")}]"
    end
  end

  def baseline(root)
    out, _err, status = Open3.capture3(
      "git", "-C", root, "describe", "--tags", "--match", "v*", "--abbrev=0",
    )
    status.success? ? out.strip : nil
  end

  def tags?(root)
    !Open3.capture3("git", "-C", root, "tag", "--list", "v*").first.strip.empty?
  end

  def violations(root, tag)
    before = surfaces_at(root, tag)
    after = surfaces_now(root)

    removed_files(before, after, tag) + changed_declarations(before, after, tag)
  end

  private

  def removed_files(before, after, tag)
    (before.keys - after.keys).sort.map do |path|
      "#{path}: signature file removed since #{tag} (NFR-4)."
    end
  end

  # NFR-4's unit is the published gem, so declarations are compared per gem: a declaration that
  # moved between two signature files of one gem is not a break.
  def changed_declarations(before, after, tag)
    (gems_of(before) & gems_of(after)).sort.flat_map do |sig_root|
      gone = gem_surface(before, sig_root) - gem_surface(after, sig_root)
      next [] if gone.empty?

      ["#{sig_root}: #{gone.length} public declaration(s) removed or narrowed since #{tag}:\n" \
       "#{gone.map { |line| "  - #{line}" }.join("\n")}\n" \
       "Regenerating a signature to silence a break is not permitted (NFR-4); bump MAJOR in " \
       "VERSIONS or restore the declaration."]
    end
  end

  def gems_of(surfaces)
    surfaces.keys.map { |path| path[%r{\Agems/[^/]+/sig}] }.uniq
  end

  def gem_surface(surfaces, sig_root)
    surfaces.select { |path, _| path.start_with?("#{sig_root}/") }.values.flatten.sort.uniq
  end

  def surface(path, content)
    buffer = RBS::Buffer.new(name: path, content: content)
    _, _, declarations = RBS::Parser.parse_signature(buffer)
    Surface.of(declarations)
  rescue RBS::ParsingError => error
    ["#{path} does not parse: #{error.message}"]
  end

  def surfaces_at(root, tag)
    listing, = Open3.capture3("git", "-C", root, "ls-tree", "-r", "--name-only", tag, "gems")
    listing.split("\n").grep(%r{\Agems/[^/]+/sig/.*\.rbs\z}).to_h do |path|
      content, = Open3.capture3("git", "-C", root, "show", "#{tag}:#{path}")
      [path, surface(path, content)]
    end
  end

  def surfaces_now(root)
    Dir.glob("gems/*/sig/**/*.rbs", base: root).to_h do |path|
      [path, surface(path, File.read(File.join(root, path)))]
    end
  end
end
