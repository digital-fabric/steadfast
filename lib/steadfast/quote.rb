# frozen_string_literal: true

require 'debug_inspector'

module Steadfast
  module Quote
    extend self

    # @param binding [Binding] unquote binding
    # @return [Ruby::Prism::Node]
    def quote(binding = nil, &block)
      raise Steadfast::Error, "No block given" if !block

      ast = Steadfast.to_ast(block).block
      quoted = Steadfast.rewrite(ast) { |n| __quote_rewrite__(n, binding) }
      if quoted.is_a?(Ruby::Prism::BlockNode)
        statements = quoted.body
        if statements.body.size == 1
          return statements.body[0]
        else
          return statements
        end
      end
      quoted
    end

    def unquote(value, location = nil)
      __quote_rewrite_unquote_convert_value__(value, location)
    end
    
    private

    def __quote_caller_binding__(idx = 3)
      DebugInspector.open { # frame 2
        it.frame_binding(idx) #frame 1
      }
    end

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
