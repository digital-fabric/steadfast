# frozen_string_literal: true

module Steadfast
  # Quote implements the quote / unquote code quoting tools. The quote/unquote
  # pair of coding tools permits creation of code templates.
  module Quote
    extend self

    # Quotes the code in the given block, interpolating all unquote expressions.
    # Returns the resulting AST. The unquote call is used to perform a
    # computation at the time of building the AST. The result of unquote is an
    # object that can be literalized (See #unquote). A call to unquote can also
    # be used to inject an AST into the code. The quote method takes a binding,
    # which is then used for any unquote computations.
    #
    # Example:
    #
    #     i = 4
    #     ast = Steadfast.quote(binding) { ->(x) { unquote(i) + x } }
    #     l = Steadfast.eval_ast(ast) #=> ->(x) { 4 + x }
    #     l + 3 #=> 7
    #
    # A call to unquote can also be in the form of a block, e.g. if the
    # computation consists of more than one statement. Nested quote calls can be
    # made in order to compute an AST that can be injected into the quoted code.
    # Alternating calls to unquote and quote can be nested arbitrarily.
    #
    # Example:
    #
    #     i = 4
    #     ast = Steadfast.quote(binding) {
    #       x = unquote {
    #         j = i + 3
    #         quote { (x + unquote(j)) }
    #       }
    #     }
    #
    # Nested calls to unquote and quote should be unqualified (i.e. quote
    # instead of Steadfast.quote). In addition, nested calls to quote should not
    # provide a binding, just a block. They will automatically inherit the
    # binding of the outermost quote.
    #
    # @param binding [Binding, nil] binding for unquote computation
    # @return [Ruby::Prism::Node] quoted code
    def quote(binding, &block)
      raise Steadfast::Error, "No block given" if !block

      ast = Steadfast.to_ast(block)
      statements = __quote_select_statements_node__(statements)
      raise Steadfast::Error, "Block can't be quoted" if !ast

      quoted = Steadfast.rewrite(ast) { |n|
        next n if !(n in Ruby::Prism::CallNode(receiver: nil, name: :unquote))

        __unquote_evaluate__(n, binding)
      }

      __quote_normalize_return_value__(quoted)
    end

    # Returns the AST for the given literal value. The value should be one of
    # the builtin types: true, false, nil, String, Float, Integer, Symbol,
    # Array, Hash, Module, Class, or Ruby::Prism::Node (an AST). If value is an
    # AST, unquote will return it. All other values are converted to an AST
    # representation as literal values.
    #
    # If a node location is provided, the resulting AST will use that location
    # information (filename + lineno), for purposes of providing correct
    # backtraces.
    #
    # The return value is an AST. If the unquote computation's result is an
    # array of AST nodes, it is returned wrapped in a StatementsNode.
    #
    # @param value [expr] expression to evaluate and inject into surrounding code
    # @return [Ruby::Prism::Node]
    def unquote(value, location = nil)
      __unquote_convert_value__(value, location)
    end

    private

    # Selects the StatementsNode out of the given AST node. If the
    # statementsNode contains a single statement, returns that statement.
    # Otherwise, returns the StatementsNode.
    #
    # @param node [Ruby::Prism::Node]
    # @return [Ruby::Prism::Node]
    def __quote_normalize_return_value__(node)
      statements = __quote_select_statements_node__(node)
      return node if !statements

      (statements.body.size == 1) ? statements.body[0] :  statements
    end

    # Selects the outermost StatementsNode for the given AST, according to the
    # node type.
    #
    # @param node [Ruby::Prism::Node]
    # @return [Ruby::Prism::StatementsNode, nil]
    def __quote_select_statements_node__(node)
      case node
      when Ruby::Prism::StatementsNode
        node
      when Ruby::Prism::BlockNode
        node.body
      when Ruby::Prism::CallNode
        node.block.body
      else
        nil
      end
    end

    # Evaluates the given AST node by sourcifying it and eval'ing the resulting
    # code with the given binding. The resulting value is rendered into an AST
    # and returned.
    #
    # @param node [Ruby::Prism::Node]
    # @param binding [Binding]
    # @return [Ruby::Prism::Node]
    def __unquote_evaluate__(node, binding)
      if node.arguments && (node.arguments.arguments.size == 1) && !node.block
        # unquote(expr)
        __unquote_evaluate_target_node__(node.arguments.arguments[0], binding, node)
      elsif node.block && !node.arguments
        # unquote { expr }
        __unquote_evaluate_target_node__(node.block.body, binding, node)
      else
        # unquote(), unquote(expr) { expr }
        raise ArgumentError, "Invalid unquote arguments"
      end
    end

    def __unquote_evaluate_target_node__(node, binding, location)
      node2 = __unquote_rewrite_nested_quote__(node, binding)
      v = Steadfast.eval_ast(node2, nil, binding)
      __unquote_convert_value__(v, location)
    end

    # Rewrites nested calls to quote inside an unquote block or expression.
    #
    # @param node [Ruby::Prism::Node]
    # @param binding [Binding]
    # @return [Ruby::Prism::Node]
    def __unquote_rewrite_nested_quote__(node, binding)
      Steadfast.rewrite(node) { |n2|
        next n2 if !(n2 in Ruby::Prism::CallNode(receiver: nil, name: :quote))

        raise ArgumentError, "Invalid arguments in call to quote" if n2.arguments
        raise ArgumentError, "Missing block in call to quote" if !n2.block

        n3 = Steadfast.make_node("Steadfast::Quote.quote(binding) do\nnil \nend", location: n2)
        Steadfast.rewrite(n3, n3.block.body => n2.block.body)
      }
    end

    # Returns an AST for the given value. This method converts the result of the
    # unquote computation into an AST.
    #
    # @param value [any]
    # @param location [Ruby::Prism::Location]
    # @return [Ruby::Prism::Node]
    def __unquote_convert_value__(value, location)
      case value
      when Integer, Float, String, Symbol, Range, Regexp, nil, true, false, Hash, Class, Module
        Steadfast.make_literal(value, location:)
      when Array
        if value.first.is_a?(Ruby::Prism::Node)
          return Steadfast.make_statements(value)
        end
        Steadfast.make_literal(value, location:)
      when Ruby::Prism::Node
        value
      else
        raise Steadfast::Error, "Don't know how to unquote #{value.inspect}"
      end
    end
  end
end
