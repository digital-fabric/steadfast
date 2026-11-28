# frozen_string_literal: true

module Steadfast
  module AST
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

    # Evaluates the given AST in the context of the given receiver, class or
    # binding. If the receiver: option is given, an instance_eval is performed.
    # If the class: option is given, a class_eval is performed. Otherwise, the
    # given binding: is used for a normal eval. If no binding is given, no
    # binding is passed to eval.
    #
    # @param ast [Ruby::Prism::Node]
    # @param receiver: [any, nil] instance_eval receiver
    # @param class: [Class, nil] class_eval receiver
    # @param binding: [Binding, nil] binding
    # @return [any]
    def eval_ast(ast, source_location: nil, **opts)
      raise ArgumentError, "Not an AST" if !ast.is_a?(Ruby::Prism::Node)

      source_location = compute_eval_source_location(source_location)
      src = to_source(ast, source_location:, sourcemap: true, frozen_string_literal: true)
      if (receiver = opts[:receiver])
        receiver.instance_eval(src, *source_location)
      elsif (receiver = opts[:class])
        receiver.class_eval(src, *source_location)
      else
        eval(src, opts[:binding], *source_location)
      end
    end

    # Computes the source location (filename and line no) for the given
    # source_location spec. If source_location is nil, computes a random
    # filename. If source_location is caller, returns the location of the
    # callsite to eval_ast. Otherwise returns the given source location, with
    # the lineno decremented (in order to compensate for the
    # frozen_string_literal comment emitted before the code.
    #
    # @param source_location [Array, nil, :caller]
    # @return [Array] [filename, lineno]
    def compute_eval_source_location(source_location)
      case source_location
      in nil
        # Important: ideally we'd set the source location line no to 0 (to
        # compensate for the #frozen_string_literal comment at the top).
        # However, while `eval` respects a starting lineno set to 0, Prism does
        # not, which can lead to off-by-one lineno in exception backtraces for
        # synthetic ASTs.
        ["(steadfast-#{SecureRandom.hex(4)})", 1]
      in :caller
        # Wwhen source_location is not nil, we do decrement the start lineno.
        # Hopefully some day this wart will be removed from Ruby.G
        l = caller_locations[1]
        [l.path, l.lineno - 1]
      in [String => filename, Integer => lineno]
        [filename, lineno - 1]
      else
        raise ArgumentError, "Invalid source_location given"
      end
    end

    # Visits the given AST, passing each node in the AST to the given block.
    #
    # @param ast [Ruby::Prism::Node]
    # @return [void]
    def walk(ast, &)
      ast.accept(Visitor.new(&))
      ast
    end

    # Visits the given AST, passing each node in the AST to the given block.
    # Returns the first node for which the block returns true.
    #
    # @param ast [Ruby::Prism::Node]
    # @return [Ruby::Prism::Node, nil]
    def find(ast, &block)
      ast.accept(Visitor.new { return it if block.(it) })
      nil
    end

    # Visits the given AST, passing each node in the AST to the given block.
    # Returns all nodes for which the block returns true.
    #
    # @param ast [Ruby::Prism::Node]
    # @return [Array<Ruby::Prism::Node>]
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
