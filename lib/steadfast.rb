# frozen_string_literal: true

require 'securerandom'

require 'steadfast/source_mapping'
require 'steadfast/sourcifier'
require 'steadfast/visitor'
require 'steadfast/rewriter'
require 'steadfast/make'
require 'steadfast/quote'

# Tell Ruby to keep script lines in memory, so calling Proc#syntax_tree or
# Method#syntax_tree will work.
RubyVM.keep_script_lines = true

# Steadfast is a metaprogramming gem for Ruby. Steadfast provides a
# general-purpose mecehanism for generating and rewriting Ruby code at runtime.
module Steadfast
  # Extensions to Ruby::Prism::Source
  module PrismSourceExtensions

    # The __filename__ attribute lets us track the source location for a given
    # AST.
    attr_accessor :__filename__
  end
  ::Ruby::Prism::Source.include(PrismSourceExtensions)

  # A base error class for Steadfast errors
  class Error < StandardError
  end

  class << self
    include Steadfast::Make

    # Returns an AST for the given object.
    #
    # @param obj [Proc, Method, UnboundedMethod, Ruby::Prism::Node]
    # @return [Ruby::Prism::Node]
    def to_ast(obj)
      case obj
      when Proc, Method, UnboundMethod
        ast = obj.syntax_tree
        raise Steadfast::Error, "AST not found for given object" if !ast

        set_source_filename(ast, obj)
        ast
      when Ruby::Prism::Node
        obj
      else
        raise ArgumentError, "Invalid object type"
      end
    end

    # Returns the source code to the given object by sourcifying its AST.
    #
    # @param obj [Proc, Method, UnboundedMethod, Ruby::Prism::Node]
    # @return [String]
    def to_source(obj, **opts)
      ast = to_ast(obj)
      Sourcifier.new(**opts).to_source(ast)
    end

    # Rewrites the given AST using the given hash of node replacements or a
    # rewrite block. Returns either the original AST, or a copy with changes.
    #
    # @param ast [Ruby::Prism::Node]
    # @param replacements [Hash]
    # @return [Ruby::Prism::Node]
    def rewrite(ast, **replacements, &block)
      Rewriter.rewrite(ast, **replacements, &block)
    end

    # Evaluates the given AST in the context of the given receiver or binding.
    #
    # @param ast [Ruby::Prism::Node]
    # @param eval_receiver [any]
    # @param eval_binding [Binding, nil]
    # @return [any]
    def eval_ast(ast, eval_receiver = nil, eval_binding = nil, source_location: nil)
      raise ArgumentError, "Not an AST" if !ast.is_a?(Ruby::Prism::Node)

      case source_location
      when nil
        # Important: ideally we'd set the source location line no to 0 (to
        # compensate for the #frozen_string_literal comment at the top).
        # However, while `eval` respects a starting lineno set to 0, Prism does
        # not, which can lead to off-by-one line nos in exception backtraces for
        # synthetic ASTs.
        # 
        # Note that when source_location is not nil, we do decrement the start
        # lineno. Hopefully some day this wart will be removed from Ruby.G
        source_location = ["(steadfast-#{SecureRandom.hex(4)})", 1]
      when :caller
        l = caller_locations[0]
        source_location = [l.path, l.lineno - 1]
      else
        source_location = [source_location[0], source_location[1] - 1]
      end
      src = to_source(ast, source_location:, sourcemap: true, frozen_string_literal: true)
      if eval_receiver
        eval_receiver.instance_eval(src, source_location[0], source_location[1])
      else
        eval(src, eval_binding || binding, source_location[0], source_location[1])
      end
    end

    def walk(ast, &)
      ast.accept(Visitor.new(&))
      ast
    end

    def find(ast, &block)
      ast.accept(Visitor.new { return it if block.(it) })
      nil
    end

    def find_all(ast, &block)
      nodes = []
      ast.accept(Visitor.new { nodes << it if block.(it) })
      nodes
    end

    private

    # Sets the source filename for the given ast to the source location of the
    # given proc or method.
    #
    # @param ast [Ruby::Prism::Node]
    # @param obj [Proc, Method]
    # @return [void]
    def set_source_filename(ast, obj)
      source = ast.send(:source)
      source.__filename__ ||= obj.source_location.first
    end

    # Finds the AST for the given proc. This method is currently not in use, but
    # we may eventually use this code in order to provide backward compatibility
    # for Ruby < 4.1.
    #
    # @param proc [Proc]
    # @return [Ruby::Prism::Node]
    def proc_ast(proc)
      fn, lineno = proc.source_location
      pr = Prism.parse(get_source(fn), filepath: fn)
      program = pr.value

      Finder.find(program, proc) do
        on(:lambda) do |node|
          found!(node) if node.location.start_line == lineno
          super(node)
        end
        on(:block) do |node|
          found!(node) if node.location.start_line == lineno
          super(node)
        end
        on(:call) do |node|
          case node.name
          when :proc, :lambda
            found!(node) if node.block && node.block.location.start_line == lineno
          end
          super(node)
        end
      end
    rescue Errno::ENOENT
      raise Sirop::Error, "Could not get source for proc"
    end

    # Finds the AST for the given method. This method is currently not in use,
    # but we may eventually use this code in order to provide backward
    # compatibility for Ruby < 4.1.
    #
    # @param method [Method, UnboundMethod]
    # @return [Ruby::Prism::Node]
    def method_ast(method)
      fn, lineno = method.source_location
      pr = Prism.parse(get_source(fn), filepath: fn)
      program = pr.value

      Finder.find(program, method) do
        on(:def) do |node|
          found!(node) if node.name == method.name && node.location.start_line == lineno
          super(node)
        end
      end
    end

    # Returns the content of the given filename. Returns the IRB line buffer if
    # '(irb)' is given. This method is not currently used.
    #
    # @param fn [String]
    # @return [String] source code
    def get_source(fn)
      return get_irb_source if fn == '(irb)'

      IO.read(fn)
    end

    # Returns the IRB line buffer (the source code for the current IRB session.)
    # This method is currently not used.
    #
    # @return [String] IRB line buffer
    def get_irb_source
      io = IRB.CurrentContext.io
      last_line = io.instance_variable_get(:@line_no)
      (1..last_line).map { io.line(it) }.join
    end
  end
end
