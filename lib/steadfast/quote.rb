# frozen_string_literal: true

module Steadfast
  module Quote
    extend self

    # Quotes the code in the given block, interpolating all unquote expressions.
    # Returns the resulting AST. The unquote call is used to perform a
    # computation at the time of building the AST. The result of unquote is an
    # object that can be literalized, that is premitive values: true, false,
    # nil, and instances of Integer, Symbol, String, Regexp, Array, Hash, Module
    # and Class. an unquote can also compute an AST and it will be embedded in
    # place. In order to be able to unquote local and instance variables, the
    # local binding must be provided. 
    # 
    # Example:
    # 
    #     i = 4
    #     ast = Steadfast.quote(binding) { ->(x) { unquote(i) + x } }
    #     l = Steadfast.eval_ast(ast) #=> ->(x) { 4 + x }
    #     l + 3 #=> 7
    #
    # An call to unquote can also be in the form of a block, if the computation
    # consists of more than one statement:
    # 
    #     ast = Steadfast.quote(binding) {
    # }
    # 
    # @param binding [Binding, nil] unquote binding
    # @return [Ruby::Prism::Node]
    def quote(binding, &block)
      raise Steadfast::Error, "No block given" if !block

      ast = Steadfast.to_ast(block)
      if ast.is_a?(Ruby::Prism::CallNode)
        ast = ast.block.body
      elsif ast.is_a?(Ruby::Prism::BlockNode)
        ast = ast.body
      else
        raise Steadfast::Error, "Block can't be quoted"
      end
      quoted = Steadfast.rewrite(ast) { |n| __quote_rewrite__(n, binding) }
      __quote_select_returned_value__(quoted)
    end

    def __quote_select_returned_value__(ast)
      case ast
      when Ruby::Prism::StatementsNode
        statements = ast
      when Ruby::Prism::BlockNode
        statements = ast.body
      when Ruby::Prism::CallNode
        statements = ast.block.body
      else
        return ast
      end
      (statements.body.size == 1) ? statements.body[0] :  statements
    end

    def unquote(value, location = nil)
      __quote_rewrite_unquote_convert_value__(value, location)
    end
    
    private

    def __quote_rewrite__(n, binding)
      case n
      in Ruby::Prism::CallNode(receiver: nil, name: :unquote)
        __quote_rewrite_unquote__(n, binding)
      else
        n
      end
    end

    def __quote_rewrite_unquote__(n, binding)
      if n.arguments && (n.arguments.arguments.size == 1) && !n.block
        # 
        arg = __quote_rewrite_unquote_expr__(n.arguments.arguments[0], binding)
        v = Steadfast.eval_ast(arg, nil, binding)
        __quote_rewrite_unquote_convert_value__(v, n)
      elsif n.block && !n.arguments
        ast = __quote_rewrite_unquote_expr__(n.block.body, binding)
        v = Steadfast.eval_ast(n.block.body, nil, binding)
        __quote_rewrite_unquote_convert_value__(v, n)
      else
        raise ArgumentError, "Invalid unquote arguments"
      end
    end

    def __quote_rewrite_unquote_expr__(ast, binding)
      Steadfast.rewrite(ast) { |n|
        next n if !(n in Ruby::Prism::CallNode(receiver: nil, name: :quote))

        __quote_rewrite_unquote_inner_quote__(n, binding)
      }
    end

    def __quote_rewrite_unquote_inner_quote__(n, binding)
      raise ArgumentError, "Invalid arguments in call to quote" if n.arguments
      raise ArgumentError, "Missing block in call to quote" if !n.block

      n2 = Steadfast.make_node("Steadfast::Quote.quote(binding) do\n1 \nend", location: n)
      Steadfast.rewrite(n2, n2.block.body => n.block.body)
    end

    def __quote_rewrite_unquote_convert_value__(v, location)
      case v
      when Integer, Float, String, Symbol, Range, Regexp, nil, true, false, Hash, Class, Module
        Steadfast.make_literal(v, location:)
      when Array
        if v.first.is_a?(Ruby::Prism::Node)
          Steadfast.make_statements(v)
        else
          Steadfast.make_literal(v, location:)
        end
      when Ruby::Prism::Node
        v
      else
        raise Steadfast::Error, "Don't know how to unquote #{v.inspect}"
      end
    end
  end
end
