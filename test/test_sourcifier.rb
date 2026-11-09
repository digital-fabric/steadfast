# frozen_string_literal: true

require_relative './helper'
require 'securerandom'

class SourcifierTest < Minitest::Test
  SYNTAX_FIXTURES_PATH = File.join(FIXTURES_PATH, 'syntax')
  DEBUG = !!ENV['DEBUG']

  Dir["#{SYNTAX_FIXTURES_PATH}/*.rb"].each do |fn|
    name = File.basename(fn).match(/^(.+)\.rb$/)[1]
    src = IO.read(fn)
    define_method(:"test_sourcify_#{name}") {
      proc = eval(src, binding, fn)
      node = Steadfast.to_ast(proc)
      assert_kind_of Ruby::Prism::Node, node

      p node if DEBUG
      code = Steadfast.to_source(node)
      puts code if DEBUG

      assert_source_match src, code
    }
  end

  def test_proc_parameter_injection
    skip

    p1 = -> { 1 }
    node = Steadfast.to_ast(p1)
    assert_kind_of Ruby::Prism::LambdaNode, node
    assert_equal '-> { 1 }', Steadfast.to_source(node).strip
    node.inject_parameters('foo')
    assert_equal '->(foo) { 1 }', Steadfast.to_source(node).strip

    p2 = ->() { 2 }
    node = Steadfast.to_ast(p2)
    assert_kind_of Ruby::Prism::LambdaNode, node
    assert_equal '->() { 2 }', Steadfast.to_source(node).strip
    node.inject_parameters('foo')
    assert_equal '->(foo) { 2 }', Steadfast.to_source(node).strip

    p3 = -> (a) { 3 }
    node = Steadfast.to_ast(p3)
    assert_kind_of Ruby::Prism::LambdaNode, node
    assert_equal '-> (a) { 3 }', Steadfast.to_source(node).strip
    node.inject_parameters('foo')
    assert_equal '-> (foo, a) { 3 }', Steadfast.to_source(node).strip

    p4 = -> (a:, b: 2) { 4 }
    node = Steadfast.to_ast(p4)
    assert_kind_of Ruby::Prism::LambdaNode, node
    # binding.irb
    assert_equal '-> (a:, b: 2) { 4 }', Steadfast.to_source(node).strip
    node.inject_parameters('foo')
    assert_equal '-> (foo, a:, b: 2) { 4 }', Steadfast.to_source(node).strip
  end
end

class SourcifierPrismTest < Minitest::Test
  PRISM_FIXTURES_PATH = File.join(FIXTURES_PATH, 'prism')
  p path: PRISM_FIXTURES_PATH

  Dir["#{PRISM_FIXTURES_PATH}/*.txt"].each do |fn|
    name = File.basename(fn).match(/^(.+)\.txt$/)[1]
    src = IO.read(fn)
    define_method(:"test_sourcify_prism_#{name}") {
      proc = eval(src, binding, fn)
      node = Steadfast.to_ast(proc)
      assert_kind_of Ruby::Prism::Node, node

      p node if ENV['DEBUG'] == '1'
      code = Steadfast.to_source(node)
      puts code if ENV['DEBUG'] == '1'

      assert_source_match src, code
    }
  end
end

class SourcifierSourceMapTest < Minitest::Test
  class Mutator
    def initialize(mutate_block)
      @mutate_block = mutate_block
    end
    
    def method_missing(sym, n)= sym !~ /^visit_/ ? super(sym, n) : visit(n)
  
    def visit(n)
      n2 = @mutate_block.(n)
      return n2 if n2 != n
  
      mutations = {}
      n.deconstruct_keys(nil).each do |k, v|
        if v.is_a?(Ruby::Prism::Node)
          res = visit(v)
          mutations[k] = res if (res != v)
        elsif v.is_a?(Array) && v[0].is_a?(Ruby::Prism::Node)
          v2 = v.map { visit(it) }
          mutations[k] = v2 if v2 != v
        end
      end
      mutations.empty? ? n : n.copy(**mutations)
    end
  end
  
  def mutate(ast, **mutations, &block)
    block ||= ->(n) do
      if n.is_a?(Ruby::Prism::StatementsNode) && mutations.has_key?(n.body)
        v = mutations[n.body]
        v = v.body if v.is_a?(Ruby::Prism::StatementsNode)
        n.copy(body: v)
      else
        mutations.has_key?(n) ? mutations[n] : n
      end
    end
    ast.accept(Mutator.new(block))
  end

  class E1 < StandardError
  end

  class E2 < StandardError
  end

  class E3 < StandardError
  end

  E1_LINE = __LINE__ + 4
  L1 = ->(x) do
    case x
    when 1
      raise E1, "E1"
    when 2
      foo
    when 3
      bar
    end
  end

  E2_LINE = __LINE__ + 1
  L2 = -> { raise E2, "E2" }

  E3_LINE = __LINE__ + 2
  L3 = -> {
    raise E3, "E3"
  }

  L4 = ->(x) {
    [nil, (raise E1, "E1"), foo, bar]
  }

  def mutated_lambda(l)
    ast1 = Steadfast.to_ast(l)
    ast2 = mutate(ast1) do |n|
      case n
      in Ruby::Prism::CallNode(receiver: nil, name: :foo)
        Steadfast.to_ast(L2).body.body[0]
      in Ruby::Prism::CallNode(receiver: nil, name: :bar)
        Steadfast.to_ast(L3).body.body[0]
      else
        n
      end
    end
    @source_location = ["(mutated_lambda-#{SecureRandom.hex(4)})", __LINE__ + 1]
    src = Steadfast.to_source(ast2, source_location: @source_location, sourcemap: true)
    eval(src, binding, *@source_location)
  end

  def test_mutated_lambda
    l = mutated_lambda(L1)
    assert_raises(E1) { l.(1) }
    assert_raises(E2) { l.(2) }
    assert_raises(E3) { l.(3) }
  end

  def catch_error
    yield
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

  def test_mutated_lambda_exception_backtrace
    l = mutated_lambda(L1)

    e = catch_error { l.(1) }
    assert_kind_of E1, e
    bt = Steadfast.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E1_LINE, line

    e = catch_error { l.(2) }
    assert_kind_of E2, e
    bt = Steadfast.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E2_LINE, line
    
    e = catch_error { l.(3) }
    assert_kind_of E3, e
    bt = Steadfast.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E3_LINE, line
  end
end
