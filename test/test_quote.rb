# frozen_string_literal: true

require_relative './helper'

class QuoteTest < Minitest::Test
  include Steadfast::Quote

  def test_quote_no_unquote
    n = quote { 1 }
    assert_kind_of Ruby::Prism::IntegerNode, n
    assert_equal 1, Steadfast.eval_ast(n)
  end

  def test_quote_no_unquote_multiple_statements
    n = quote { 1; :foo }
    assert_kind_of Ruby::Prism::StatementsNode, n
    assert_equal "1\n:foo", Steadfast.to_source(n)
  end

  def test_quote_unquote_lvar
    x = 4
    n = quote(binding) { 3 + unquote(x) }
    assert_kind_of Ruby::Prism::CallNode, n
    assert_equal 7, Steadfast.eval_ast(n)
  end
end
