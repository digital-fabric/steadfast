# frozen_string_literal: true

require_relative './helper'

class QuoteTest < Minitest::Test
  include Steadfast::Quote

  def foo; :foo; end
  def bar(x); [x]; end

  def test_quote_no_unquote
    n = quote(nil) { 1 }
    assert_kind_of Ruby::Prism::IntegerNode, n
    assert_equal 1, Steadfast.eval_ast(n)

    n = quote(nil) { true }
    assert_kind_of Ruby::Prism::TrueNode, n
    assert_equal true, Steadfast.eval_ast(n)

    n = quote(nil) { nil }
    assert_kind_of Ruby::Prism::NilNode, n
    assert_nil Steadfast.eval_ast(n)

    n = quote(nil) { [1] }
    assert_kind_of Ruby::Prism::ArrayNode, n
    assert_equal [1], Steadfast.eval_ast(n)

    n = quote(nil) { 'abc' }
    assert_kind_of Ruby::Prism::StringNode, n
    assert_equal 'abc', Steadfast.eval_ast(n)

    n = quote(nil) { "abc#{'def'}" }
    assert_kind_of Ruby::Prism::InterpolatedStringNode, n
    assert_equal 'abcdef', Steadfast.eval_ast(n)

    n = quote(nil) { foo }
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :foo, Steadfast.eval_ast(n, self)
  end

  def test_quote_no_unquote_multiple_statements
    n = quote(nil) { 1; :foo }
    assert_kind_of Ruby::Prism::StatementsNode, n
    assert_equal "1\n:foo", Steadfast.to_source(n)
  end

  def test_quote_unquote_literal
    n = quote(binding) { unquote(2) }
    assert_kind_of Ruby::Prism::IntegerNode, n
    assert_equal 2, Steadfast.eval_ast(n, self)

    n = quote(binding) { unquote([:a,  1, [:b, 2]]) }
    assert_kind_of Ruby::Prism::ArrayNode, n
    assert_equal([:a,  1, [:b, 2]], Steadfast.eval_ast(n, self))

    n = quote(binding) { unquote({ a: 1, b: 2}) }
    assert_kind_of Ruby::Prism::HashNode, n
    assert_equal({ a: 1, b: 2}, Steadfast.eval_ast(n, self))
  end

  def test_quote_unquote_from_binding
    x = 4
    n = quote(binding) { 3 + unquote(x) }
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal 7, Steadfast.eval_ast(n)
  end

  def test_quote_unquote_non_literal
    x = Object.new
    assert_raises(Steadfast::Error) { quote(binding) { 3 + unquote(x) } }
  end

  def test_quote_unquote_method_call
    n = quote(binding) { unquote(foo) }
    assert_kind_of Ruby::Prism::SymbolNode, n
    assert_equal :foo, Steadfast.eval_ast(n)
  end

  def test_quote_unquote_block
    n = quote(binding) { unquote { :foo } }
    assert_kind_of Ruby::Prism::SymbolNode, n
    assert_equal :foo, Steadfast.eval_ast(n)

    n = quote(binding) { unquote { foo } }
    assert_kind_of Ruby::Prism::SymbolNode, n
    assert_equal :foo, Steadfast.eval_ast(n)

    buf = []
    n = quote(binding) { unquote { buf << 1; buf << foo; buf.join(',') } }
    assert_kind_of Ruby::Prism::StringNode, n
    assert_equal '1,foo', Steadfast.eval_ast(n)
  end

  def test_quote_unquote_invalid_args
    assert_raises(ArgumentError) { quote(nil) { unquote(1, 2) } }
    assert_raises(ArgumentError) { quote(nil) { unquote(1) { 2 } } }
    assert_raises(ArgumentError) { quote(nil) { unquote() } }
  end

  def test_quote_unquote_node
    n = quote(binding) { unquote { Steadfast.make_literal([1]) } }
    assert_kind_of Ruby::Prism::ArrayNode, n
    assert_equal [1], Steadfast.eval_ast(n)

    l = ->(x) { x ** 2 }
    n = quote(binding) { unquote { Steadfast.to_ast(l) } }
    assert_kind_of Ruby::Prism::LambdaNode, n
    l2 = Steadfast.eval_ast(n)
    assert_equal 9, l2.(3)
  end

  def test_quote_unquote_array_of_nodes
    a = [42, 43].map { Steadfast.make_literal(it) }
    n = quote(binding) { unquote(a) }
    assert_kind_of Ruby::Prism::StatementsNode, n
    assert_source_match "42; 43", Steadfast.to_source(n)
  end
end

class UnquoteTest < Minitest::Test
  include Steadfast::Quote

  def test_unquote_literal
    n = unquote(2)
    assert_kind_of Ruby::Prism::IntegerNode, n
    assert_equal 2, Steadfast.eval_ast(n)

    n = unquote([:foo])
    assert_kind_of Ruby::Prism::ArrayNode, n
    assert_equal [:foo], Steadfast.eval_ast(n)

    n = unquote(Steadfast.to_ast(->() { 42 }))
    assert_kind_of Ruby::Prism::LambdaNode, n
    assert_equal 42, Steadfast.eval_ast(n).()
  end
end

class QuoteScenarioAdder < Minitest::Test
  include Steadfast::Quote

  def make_adder(v)
    ast = quote(binding) { ->(x) { x + unquote(v) } }
    Steadfast.eval_ast(ast)
  end

  def test_quote_scenario_adder
    a = make_adder(42)
    assert_kind_of Proc, a
    assert_equal 47, a.(5)
  end
end

class QuoteScenarioValidator < Minitest::Test
  include Steadfast::Quote

  def create_validator(*conds)
    @raise_line = __LINE__ + 3
    ast = quote(binding) {
      ->(v) {
        unquote(conds.map { |c| quote { raise unless unquote(c) === v } })
        v
      }
    }
    Steadfast.eval_ast(ast)
  rescue => e
    p e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    bt.each { puts it }
    exit!(1)
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

  def test_quote_scenario_validator
    v = create_validator(String, /abc/)
    assert_kind_of Proc, v
    assert_equal 'abc', v.('abc')
    assert_raises(RuntimeError) { v.(1) }
    assert_raises(RuntimeError) { v.('def') }

    call_line = __LINE__ + 1
    e = capture_exception { v.('Abc') }
    assert_kind_of RuntimeError, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    assert_equal [__FILE__, @raise_line], bt_entry_location(bt[0])
    assert_equal [__FILE__, call_line], bt_entry_location(bt[1])
  end
end

class SteadfastQuoteTest < Minitest::Test
  def test_steadfast_quote
    ast = Steadfast.quote(binding) { 42 }
    assert_kind_of Ruby::Prism::IntegerNode, ast
    assert_equal 42, Steadfast.eval_ast(ast)
  end

  def test_steadfast_unquote
    ast = Steadfast.unquote(42)
    assert_kind_of Ruby::Prism::IntegerNode, ast
    assert_equal 42, Steadfast.eval_ast(ast)
  end
end
