# frozen_string_literal: true

require 'debug_inspector'

module Steadfast
  module Quote
    # @param binding [Binding, nil] unquote binding
    # @return [Ruby::Prism::Node]
    def quote(binding = nil, &block)
      raise Steadfast::Error, "No block given" if !block

      binding ||= __quote_caller_binding__(4)
      raise Steadfast::Error, "Invalid binding" if !binding.is_a?(Binding)

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
        arg = n.arguments.arguments[0]
        v = Steadfast.eval_ast(arg, nil, binding)
        __quote_rewrite_unquote_convert_value__(v, n)
      elsif n.block && !n.arguments
        v = Steadfast.eval_ast(n.block.body, nil, binding)
        __quote_rewrite_unquote_convert_value__(v, n)
      else
        raise ArgumentError, "Invalid unquote arguments"
      end
    end

    def __quote_rewrite_unquote_convert_value__(v, location)
      case v
      when Integer, Float, String, Symbol, Range, Regexp, nil, true, false, Hash, Array
        Steadfast.make_literal(v, location:)
      when Ruby::Prism::Node
        v
      else
        raise Steadfast::Error, "Don't know how to unquote #{v.inspect}"
      end
    end
  end
end
