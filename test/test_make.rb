# frozen_string_literal: true

require_relative './helper'

class MakeNodeTest < Minitest::Test
  include Steadfast::Make

  def test_make_node_basic
    n = make_node('-> { 42 }')
    assert_kind_of Ruby::Prism::LambdaNode, n
    assert_equal 1, n.start_line
    assert_nil n.send(:source).__filename__
    assert_source_match '-> { 42 }', Steadfast.to_source(n)
    assert_equal 42, Steadfast.eval_ast(n).()
  end

  def test_make_node_with_location
    line = __LINE__ + 1
    l = -> { 3 }
    l_ast = Steadfast.to_ast(l)

    n = make_node('-> { 42 }', location: l_ast)
    assert_kind_of Ruby::Prism::LambdaNode, n
    assert_equal line, n.start_line
    assert_equal __FILE__, n.send(:source).__filename__
    assert_source_match '-> { 42 }', Steadfast.to_source(n)
    assert_equal 42, Steadfast.eval_ast(n).()
  end

  def test_make_node_bad_syntax
    assert_raises(SyntaxError) { make_node('l(abc') }
  end

  def test_make_node_lvars
    n = make_node('x')
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :x, n.name

    n = make_node('x', lvars: [:y])
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :x, n.name

    n = make_node('x', lvars: [:x])
    assert_kind_of Ruby::Prism::LocalVariableReadNode, n
    assert_equal :x, n.name
  end

  def test_make_node_binding
    x = 1
    
    n = make_node('x')
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :x, n.name

    n = make_node('y', binding:)
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :y, n.name

    n = make_node('x', binding:)
    assert_kind_of Ruby::Prism::LocalVariableReadNode, n
    assert_equal :x, n.name
  end

  def test_make_node_lvars_plus_binding
    x = 1
    
    n = make_node('x + y', binding:)
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :+, n.name
    assert_kind_of Ruby::Prism::LocalVariableReadNode, n.receiver
    assert_equal :x, n.receiver.name
    assert_kind_of Ruby::Prism::CallNode, n.arguments.arguments[0]
    assert_equal :y, n.arguments.arguments[0].name

    n = make_node('x + y', lvars: [:y])
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :+, n.name
    assert_kind_of Ruby::Prism::CallNode, n.receiver
    assert_equal :x, n.receiver.name
    assert_kind_of Ruby::Prism::LocalVariableReadNode, n.arguments.arguments[0]
    assert_equal :y, n.arguments.arguments[0].name

    n = make_node('x + y', binding:, lvars: [:y])
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :+, n.name
    assert_kind_of Ruby::Prism::LocalVariableReadNode, n.receiver
    assert_equal :x, n.receiver.name
    assert_kind_of Ruby::Prism::LocalVariableReadNode, n.arguments.arguments[0]
    assert_equal :y, n.arguments.arguments[0].name
  end

  def test_steadfast_make_node
    n = Steadfast.make_node('-> { 42 }')
    assert_kind_of Ruby::Prism::LambdaNode, n
    assert_equal 1, n.start_line
    assert_nil n.send(:source).__filename__
    assert_source_match '-> { 42 }', Steadfast.to_source(n)
    assert_equal 42, Steadfast.eval_ast(n).()
  end
end
