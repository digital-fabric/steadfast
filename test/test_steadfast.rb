# frozen_string_literal: true

require_relative './helper'
require 'securerandom'

class ToAstTest < Minitest::Test
  def test_to_ast_bad_block
    l = ->(&b) { b }
    b = l.(&:foo)
    assert_raises(Steadfast::Error) { Steadfast.to_ast(b) }
  end

  def test_to_ast_reversibility
    l1 = ->(x, y) { x + y }
    ast1 = Steadfast.to_ast(l1)
    assert_kind_of Ruby::Prism::LambdaNode, ast1

    l2 = Steadfast.eval_ast(ast1)
    assert_kind_of Proc, l2
    assert_equal 7, l2.(3, 4)

    ast2 = Steadfast.to_ast(l2)

    assert_equal Steadfast.to_source(ast1), Steadfast.to_source(ast2)
  end
end

class EvalASTTest < Minitest::Test
  def test_eval_ast_no_receiver
    x = 3
    @y = 2
    l = ->(z) { x + @y + z }

    ast = Steadfast.to_ast(l)
    l2 = Steadfast.eval_ast(ast, binding: l.binding)

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
    l2 = Steadfast.eval_ast(ast, binding: l.binding)

    assert_kind_of Proc, l2
    l2.()
    assert_equal 9, add1(7)
  end

  class MyFoo
  end

  def test_eval_ast_class_receiver
    ast = Steadfast.quote(nil) {
      def foo; :bar; end
    }
    assert_equal false, MyFoo.instance_methods.include?(:foo)
    Steadfast.eval_ast(ast, class: MyFoo)
    assert_equal true, MyFoo.instance_methods.include?(:foo)
  end

  def test_eval_ast_binding
    l = -> { x = 3; ->(y) { x + y } }.()
    ast = Steadfast.to_ast(l)

    wrapped = Steadfast.rewrite(ast) { |n|
      next n if !(n in Ruby::Prism::CallNode)

      Steadfast.quote(binding) { 3 + unquote(n) }
    }
    l2 = Steadfast.eval_ast(wrapped, binding: l.binding)
    assert_equal 13, l2.(7)

    l3 = Steadfast.eval_ast(wrapped, binding: binding)
    assert_raises(NameError) { l3.(7) }

    l4 = Steadfast.eval_ast(wrapped)
    assert_raises(NameError) { l4.(7) }
  rescue => e
    p e
    puts Steadfast::SourceMapping.translate_backtrace(e.backtrace).join("\n")
  end

  def test_eval_ast_bad_ast
    assert_raises(ArgumentError) { Steadfast.eval_ast(nil) }
    assert_raises(ArgumentError) { Steadfast.eval_ast(-> { 1 }) }
    assert_raises(ArgumentError) { Steadfast.eval_ast(42) }
    assert_raises(ArgumentError) { Steadfast.eval_ast(:foo) }
  end

  def test_eval_ast_with_source_location
    l0 = -> { 0 }
    source_location = ["(test_eval_ast_with_source_location-#{SecureRandom.hex(4)})", __LINE__ - 1]
    l1 = -> { 42 }
    ast = Steadfast.to_ast(l1)
    l2 = Steadfast.eval_ast(ast, source_location:)
    assert_equal 42, l2.()
    assert_equal source_location, l2.source_location
  end

  def test_eval_ast_caller_source_location
    l1 = -> { 42 }
    ast = Steadfast.to_ast(l1)
    source_location = [__FILE__, __LINE__ + 1]
    l2 = Steadfast.eval_ast(ast, source_location: :caller)
    assert_equal 42, l2.()
    assert_equal source_location, l2.source_location
  end

  def test_eval_ast_nil_source_location
    l1 = -> { 42 }
    ast = Steadfast.to_ast(l1)
    source_location = [__FILE__, __LINE__ + 1]
    l2 = Steadfast.eval_ast(ast)
    assert_equal 42, l2.()
    loc = l2.source_location
    assert_match /^\(steadfast-[0-9a-f]+\)$/, loc[0]
    assert_equal 2, loc[1]
  end

  def test_eval_ast_frozen_string_literal
    l1 = -> { "foo" }
    ast = Steadfast.to_ast(l1)
    l2 = Steadfast.eval_ast(ast)

    s = l2.()
    assert_equal true, s.frozen?
  end
end

class WalkTest < Minitest::Test
  P = Ruby::Prism

  def test_walk
    l = -> { loop { 42; :foo } }
    ast = Steadfast.to_ast(l)

    buf = []
    Steadfast.walk(ast) { buf << it.class }
    assert_equal [
      P::LambdaNode,
      P::StatementsNode,
      P::CallNode,
      P::BlockNode,
      P::StatementsNode,
      P::IntegerNode,
      P::SymbolNode
    ], buf
  end
end

class FindTest < Minitest::Test
  def test_find
    l = -> { loop { 42; :foo } }
    ast = Steadfast.to_ast(l)

    n = Steadfast.find(ast) { it in Ruby::Prism::StringNode }
    assert_nil n

    n = Steadfast.find(ast) { it in Ruby::Prism::SymbolNode }
    assert(n.is_a?(Ruby::Prism::SymbolNode) && n.unescaped == 'foo')
  end
end

class FindAllTest < Minitest::Test
  def test_find_all
    l = -> { loop { 42; :foo; :bar } }
    ast = Steadfast.to_ast(l)

    nn = Steadfast.find_all(ast) { it in Ruby::Prism::StatementsNode }
    assert_kind_of Array, nn
    assert_equal 2, nn.size

    nn = Steadfast.find_all(ast) { it in Ruby::Prism::StringNode }
    assert_kind_of Array, nn
    assert_equal 0, nn.size

    nn = Steadfast.find_all(ast) { it in Ruby::Prism::SymbolNode }
    assert_kind_of Array, nn
    assert_equal %w[foo bar], nn.map(&:unescaped)
  end
end
