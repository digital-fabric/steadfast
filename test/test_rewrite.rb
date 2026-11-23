# frozen_string_literal: true

require_relative './helper'
require 'securerandom'

class RewriteTest < Minitest::Test
  def test_rewrite_replacements_node_to_node
    l1 = -> { 1 }
    l2 = -> { :foo }

    assert_equal 1, l1.()
    assert_equal :foo, l2.()

    l1_ast = Steadfast.to_ast(l1)
    l2_ast = Steadfast.to_ast(l2)

    l1_statement = l1_ast.body.body[0]
    l2_statement = l2_ast.body.body[0]

    assert_kind_of Ruby::Prism::IntegerNode, l1_statement
    assert_kind_of Ruby::Prism::SymbolNode, l2_statement

    l3_ast = Steadfast.rewrite(l1_ast, l1_statement => l2_statement)
    l3 = eval(Steadfast.to_source(l3_ast))
    assert_source_match Steadfast.to_source(l2), Steadfast.to_source(l3)
    assert_equal :foo, l3.()
  end

  def test_rewrite_replacements_node_to_hash
    l1 = ->(x) { x += 1; x**2 }
    l2 = ->(y) { y }

    assert_equal 16, l1.(3)
    assert_equal 1, l2.(1)

    l1_ast = Steadfast.to_ast(l1)
    l2_ast = Steadfast.to_ast(l2)

    l1_params = l1_ast.parameters.parameters
    l2_params = l2_ast.parameters.parameters

    l1_body = l1_ast.body
    l2_body = l2_ast.body

    l3 = ->(x, y) { x + y }
    l3_body = Steadfast.to_ast(l3).body

    l4_ast = Steadfast.rewrite(
      l1_ast,
      l1_params => { requireds: [*l1_params.requireds, *l2_params.requireds] },
      l1_body => l3_body
    )

    assert_source_match Steadfast.to_source(l3), Steadfast.to_source(l4_ast)
    assert_equal 7, eval(Steadfast.to_source(l4_ast)).(3, 4)
  end

  def foo = :foo
  def bar = :bar

  def test_rewrite_method_call
    l = ->() { foo }
    assert_equal :foo, l.()

    l_bar = ->() { bar }
    assert_equal :bar, l_bar.()
    bar_call_node = Steadfast.to_ast(l_bar).body.body[0]

    ast = Steadfast.to_ast(l)
    assert_kind_of Ruby::Prism::Node, ast

    ast2 = Steadfast.rewrite(ast) { |n|
      if (n in Ruby::Prism::CallNode(receiver: nil, name: :foo))
        bar_call_node
      else
        n
      end
    }
    l2 = eval(Steadfast.to_source(ast2), binding)
    assert_equal :bar, l2.()
  end

  def test_rewrite_method_call_kwargs
    l = ->() { foo }
    assert_equal :foo, l.()

    l_bar = ->() { bar }
    assert_equal :bar, l_bar.()
    bar_call_node = Steadfast.to_ast(l_bar).body.body[0]

    ast = Steadfast.to_ast(l)
    assert_kind_of Ruby::Prism::Node, ast
    foo_call_node = ast.body.body[0]

    ast2 = Steadfast.rewrite(ast, foo_call_node => bar_call_node)
    l2 = eval(Steadfast.to_source(ast2), binding)
    assert_equal :bar, l2.()
  end
end

class RewriteInlineTest < Minitest::Test
  def make_inlined_lambda(l, inline_bodies)
    ast = Steadfast.to_ast(l)
    ast2 = Steadfast.rewrite(ast) { |n|
      if n in Ruby::Prism::CallNode(receiver: nil, name: :foo | :bar | :baz)
        ast = Steadfast.to_ast(inline_bodies[n.name])
        next ast.body.body[0] if ast
      end
      n
    }
    eval(Steadfast.to_source(ast2), l.binding)
  end

  def test_rewrite_inline
    l = ->(x) do
      case x
      when 1
        foo
      when 2
        bar
      when 3
        baz
      when 4
        bad
      end
    end

    inline_bodies = {
      foo: -> { :foo },
      bar: -> { :bar },
      baz: -> { :baz }
    }
    l2 = make_inlined_lambda(l, inline_bodies)
    assert_kind_of Proc, l2

    assert_equal :foo, l2.(1)
    assert_equal :bar, l2.(2)
    assert_equal :baz, l2.(3)
    assert_raises(NameError) { l2.(4) }
  end
end

class RewriteTailCallTest < Minitest::Test
  def make_def_node(name, params_ast)
    l = eval("-> { def #{name}(x); 1; end }")
    def_node = Steadfast.to_ast(l).body.body[0]
    def_node.copy(parameters: params_ast)
  end

  def make_loop(*statements)
    l = eval("-> { loop do; 1; end }")
    loop_node = Steadfast.to_ast(l).body.body[0]
    loop_block_body = loop_node.block.body
    Steadfast.rewrite(loop_node, loop_block_body => { body: statements })
  end

  def rewrite_with_tail_call(meth)
    ast = Steadfast.to_ast(meth)
    params = ast.parameters
    *body, tail = ast.body.body

    raise "Not a tail call method!" if !(tail.is_a?(Ruby::Prism::CallNode) && tail.name == meth.name)

    body2 = make_loop(*body, convert_tail_call(tail, params))
    ast2 = Steadfast.rewrite(ast, ast.body => { body: [body2] })
    eval(Steadfast.to_source(ast2))
  end

  def make_multi_write_node(names, values)
    l = eval("-> { #{names.join(', ')} = [nil] }")
    multi_write_node = Steadfast.to_ast(l).body.body[0]
    Steadfast.rewrite(multi_write_node, multi_write_node.value => { elements: values })
  end

  def convert_tail_call(tail, params)
    make_multi_write_node(
      [*params.requireds.map(&:name), *params.optionals.map(&:name)],
      tail.arguments.arguments
    )
  end

  def fact(n, acc = 1)
    return acc if n <= 1
    fact(n - 1, n * acc)
  end
  alias_method :orig_fact, :fact

  def test_rewrite_tail_call
    rewrite_with_tail_call(method(:fact))

    assert_source_match <<~RUBY, Steadfast.to_source(method(:fact))
      def fact(n, acc = 1)
        loop do
          return acc if n <= 1
          n, acc = [n - 1, n * acc]
        end
      end
    RUBY

    10.times {
      n = rand(1..1000)
      assert_equal orig_fact(n), fact(n)
    }
  end
end

class RewritePipeTest < Minitest::Test
  def add(x, y); x + y; end
  def mul(x, y); x * y; end
  def pow(x, y); x ** y; end

  def convert_pipe(n)
    return n if !(n in Ruby::Prism::CallNode(name: :>>))

    call_node = n.arguments.arguments[0]
    return n if !n in Ruby::Prism::CallNode

    arguments = [Steadfast.rewrite(n.receiver) { convert_pipe(it) }, call_node.arguments]
    Steadfast.rewrite(call_node, call_node.arguments => { arguments: })
  end

  def test_rewrite_pipe
    l = -> { 4 >> add(3) >> mul(6) >> pow(2) }
    l_ast = Steadfast.to_ast(l)

    p_ast = Steadfast.rewrite(l_ast) { |n| convert_pipe(n) }
    p = eval(Steadfast.to_source(p_ast))
    assert_kind_of Proc, p
    assert_equal ((4 + 3) * 6) ** 2, p.()
  end

  def test_rewrite_pipe_syntax_recursive_block
    l = -> { 4 >> add(3) >> mul(6) >> pow(2) }
    l_ast = Steadfast.to_ast(l)

    p_ast = Steadfast.rewrite(l_ast) { |n, &r|
      next n if !(n in Ruby::Prism::CallNode(name: :>>))

      call_node = n.arguments.arguments[0]
      next n if !n in Ruby::Prism::CallNode

      arguments = [Steadfast.rewrite(n.receiver, &r), call_node.arguments]
      Steadfast.rewrite(call_node, call_node.arguments => { arguments: })
    }
    p = eval(Steadfast.to_source(p_ast))
    assert_kind_of Proc, p
    assert_equal ((4 + 3) * 6) ** 2, p.()
  end
end
