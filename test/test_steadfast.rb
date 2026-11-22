# frozen_string_literal: true

require_relative './helper'
require 'securerandom'

class EvalASTTest < Minitest::Test
  def test_eval_ast_no_receiver
    x = 3
    @y = 2
    l = ->(z) { x + @y + z }

    ast = Steadfast.to_ast(l)
    l2 = Steadfast.eval_ast(ast, nil, l.binding)

    assert_kind_of Proc, l2
    assert_equal 12, l2.(7)
  end

  def test_eval_ast_receiver
    @y = 2
    l = ->() {
      def add1(x); x + @y; end
    }

    ast = Steadfast.to_ast(l)
    n = ast.body.body[0]
    l2 = Steadfast.eval_ast(ast, nil, l.binding)

    assert_kind_of Proc, l2
    l2.()
    assert_equal 9, add1(7)
  end

  def test_eval_ast_bad_ast
    assert_raises(ArgumentError) { Steadfast.eval_ast(nil) }
    assert_raises(ArgumentError) { Steadfast.eval_ast(-> { 1 }) }
    assert_raises(ArgumentError) { Steadfast.eval_ast(42) }
    assert_raises(ArgumentError) { Steadfast.eval_ast(:foo) }
  end
end
