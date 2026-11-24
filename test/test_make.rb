# frozen_string_literal: true

require_relative './helper'

class MakeNodeTest < Minitest::Test
  include Steadfast::Make

  def test_make_node
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

class MakeDefTest < Minitest::Test
  include Steadfast::Make

  def test_make_def
    l1 = -> {
      'foo'
    }
    n = make_def(:foo, body: Steadfast.to_ast(l1).find { it in Ruby::Prism::StatementsNode })
    assert_kind_of Ruby::Prism::DefNode, n
    assert_equal :foo, n.name
    assert_source_match "def foo(); 'foo'; end", Steadfast.to_source(n)

    o = Object.new
    Steadfast.eval_ast(n, o)
    assert_equal 'foo', o.foo
  end

  def capture_exception
    yield
    nil
  rescue => e
    e
  end

  def bt_entry_location(entry)
    if (m = entry.match(/^([^\:]+)\:(\d+)/))
      [m[1], m[2].to_i]
    else
      nil
    end
  end

  def test_make_def_location
    e_line = __LINE__ + 2
    l1 = -> {
      raise 'foobar'
    }
    n = make_def(:foo, body: Steadfast.to_ast(l1).find { it in Ruby::Prism::StatementsNode })
    assert_kind_of Ruby::Prism::DefNode, n
    assert_equal :foo, n.name
    assert_source_match "def foo(); raise 'foobar'; end", Steadfast.to_source(n)

    o = Object.new
    Steadfast.eval_ast(n, o)

    e = capture_exception { o.foo }
    assert_kind_of RuntimeError, e
    assert_equal 'foobar', e.message
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    assert_equal [__FILE__, e_line], bt_entry_location(bt[0])
  end

  def test_make_def_params
    l1 = ->(x, y) { x + y }
    l_ast = Steadfast.to_ast(l1)
    params = l_ast.find { it in Ruby::Prism::ParametersNode }
    body = l_ast.find { it in Ruby::Prism::StatementsNode }
    n = make_def(:add, params:, body:)
    assert_kind_of Ruby::Prism::DefNode, n
    assert_equal :add, n.name
    assert_source_match "def add(x, y); x + y; end", Steadfast.to_source(n)

    o = Object.new
    Steadfast.eval_ast(n, o)
    assert_equal 7, o.add(3, 4)
  end

  def test_make_def_invalid_name
    l1 = ->() { 42 }
    assert_raises(SyntaxError) { make_def(1, body: nil) }
    assert_raises(SyntaxError) { make_def(nil, body: nil) }
    assert_raises(SyntaxError) { make_def('1a', body: nil) }
    assert_raises(SyntaxError) { make_def('b a', body: nil) }
    assert_raises(SyntaxError) { make_def('c:a', body: nil) }
    assert_raises(SyntaxError) { make_def('D:a', body: nil) }
    assert_raises(SyntaxError) { make_def('foo(x)', body: nil) }
    assert_raises(SyntaxError) { make_def('foo; end; exit', body: nil) }
    make_def('Wd', body: nil)
    make_def('_é', body: nil)
    make_def('_ù', body: nil)
    make_def('ù', body: nil)
    make_def('zλ', body: nil)
  end

  def test_steadfast_make_def
    n = Steadfast.make_def('foo', body: nil)
    assert_kind_of Ruby::Prism::DefNode, n
  end
end

class MakeLVarReadTest < Minitest::Test
  include Steadfast::Make

  def test_make_lvar_read
    n = make_lvar_read(:foo)
    assert_kind_of Ruby::Prism::LocalVariableReadNode, n
    assert_equal :foo, n.name
  end

  def test_make_lvar_read_invalid_name
    assert_raises(SyntaxError) { make_lvar_read(1) }
    assert_raises(SyntaxError) { make_lvar_read(nil) }
    assert_raises(SyntaxError) { make_lvar_read(true) }
    assert_raises(SyntaxError) { make_lvar_read('1d') }
    assert_raises(SyntaxError) { make_lvar_read('a b')}
    assert_raises(SyntaxError) { make_lvar_read('a; exit!')}
    assert_raises(SyntaxError) { make_lvar_read('a);')}

    %w[_é _ù ù λ].each { make_lvar_read(it) }
  end

  def test_steadfast_make_lvar_read
    n = Steadfast.make_lvar_read(:foo)
    assert_kind_of Ruby::Prism::LocalVariableReadNode, n
  end
end