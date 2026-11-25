# frozen_string_literal: true

require_relative './helper'

class QuoteTest < Minitest::Test
  include Steadfast::Quote

  def foo; :foo; end
  def bar(x); [x]; end

  def test_quote_no_unquote
    n = quote { 1 }
    assert_kind_of Ruby::Prism::IntegerNode, n
    assert_equal 1, Steadfast.eval_ast(n)

    n = quote { true }
    assert_kind_of Ruby::Prism::TrueNode, n
    assert_equal true, Steadfast.eval_ast(n)

    n = quote { nil }
    assert_kind_of Ruby::Prism::NilNode, n
    assert_nil Steadfast.eval_ast(n)

    n = quote { [1] }
    assert_kind_of Ruby::Prism::ArrayNode, n
    assert_equal [1], Steadfast.eval_ast(n)

    n = quote { 'abc' }
    assert_kind_of Ruby::Prism::StringNode, n
    assert_equal 'abc', Steadfast.eval_ast(n)

    n = quote { "abc#{'def'}" }
    assert_kind_of Ruby::Prism::InterpolatedStringNode, n
    assert_equal 'abcdef', Steadfast.eval_ast(n)

    n = quote { foo }
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal :foo, Steadfast.eval_ast(n, self)
  end

  def test_quote_no_unquote_multiple_statements
    n = quote { 1; :foo }
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
    assert_raises(ArgumentError) { quote { unquote(1, 2) } }
    assert_raises(ArgumentError) { quote { unquote(1) { 2 } } }
    assert_raises(ArgumentError) { quote { unquote() } }
  end

  def test_quote_unquote_ast
    n = quote(binding) { unquote { Steadfast.make_literal([1]) } }
    assert_kind_of Ruby::Prism::ArrayNode, n
    assert_equal [1], Steadfast.eval_ast(n)

    l = ->(x) { x ** 2 }
    n = quote(binding) { unquote { Steadfast.to_ast(l) } }
    assert_kind_of Ruby::Prism::LambdaNode, n
    l2 = Steadfast.eval_ast(n)
    assert_equal 9, l2.(3)
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