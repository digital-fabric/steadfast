# frozen_string_literal: true

require 'steadfast/sourcifier'

# Tell Ruby to keep script lines in memory, so calling Proc#syntax_tree or
# Method#syntax_tree will work.
RubyVM.keep_script_lines = true

# Steadfast is a metaprogramming gem for Ruby. Steadfast provides a
# general-purpose mecehanism for generating and rewriting Ruby code at runtime.
module Steadfast
  # A base error class for Steadfast errors
  class Error < StandardError
  end

  class << self
    # Returns an AST for the given object.
    #
    # @param obj [Proc, Method, UnboundedMethod, Ruby::Prism::Node]
    # @return [Ruby::Prism::Node]
    def to_ast(obj)
      case obj
      when Proc, Method, UnboundMethod
        obj.syntax_tree
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
    def to_source(obj, **)
      obj = to_ast(obj)
      Sourcifier.new(**).to_source(obj)
    end

    private

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

    def get_source(fn)
      return get_irb_source if fn == '(irb)'

      IO.read(fn)
    end

    def get_irb_source
      io = IRB.CurrentContext.io
      last_line = io.instance_variable_get(:@line_no)
      (1..last_line).map { io.line(it) }.join
    end
  end
end
