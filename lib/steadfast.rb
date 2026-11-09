# frozen_string_literal: true

require 'steadfast/sourcifier'

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
    # Returns the global Steadfast source map hash. Currently *not* thread-safe.
    # 
    # @return [Hash] source map
    def sourcemap
      @sourcemap ||= {}
    end

    # Translates entries in the given backtrace according to the global source
    # map.
    #
    # @param bt [Array<String>] backtrace
    # @return [Array<String>] translated source map
    def translate_backtrace(bt)
      bt.map {
        if (m = it.match(/^(.+)(\:in.+)$/)) && (loc = sourcemap[m[1]])
          "#{sourcemap[m[1]]}#{m[2]}"
        else
          it
        end
      }
    end

    # Returns an AST for the given object.
    #
    # @param obj [Proc, Method, UnboundedMethod, Ruby::Prism::Node]
    # @return [Ruby::Prism::Node]
    def to_ast(obj)
      case obj
      when Proc, Method, UnboundMethod
        obj.syntax_tree.tap { set_source_filename(it, obj) }
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

    private

    # Sets 
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
