# frozen_string_literal: true

require_relative './helper'
require 'securerandom'

class SourcifierTest < Minitest::Test
  SYNTAX_FIXTURES_PATH = File.join(FIXTURES_PATH, 'syntax')
  DEBUG = !!ENV['DEBUG']

  Dir["#{SYNTAX_FIXTURES_PATH}/*.rb"].each do |fn|
    name = File.basename(fn).match(/^(.+)\.rb$/)[1]
    src = IO.read(fn)
    define_method(:"test_sourcifier_#{name}") {
      proc = eval(src, binding, fn)
      node = Steadfast.to_ast(proc)
      assert_kind_of Ruby::Prism::Node, node

      p node if DEBUG
      code = Steadfast.to_source(node)
      puts code if DEBUG

      assert_source_match src, code
    }
  end
end

class SourcifierPrismTest < Minitest::Test
  PRISM_FIXTURES_PATH = File.join(FIXTURES_PATH, 'prism')

  Dir["#{PRISM_FIXTURES_PATH}/*.txt"].each do |fn|
    name = File.basename(fn).match(/^(.+)\.txt$/)[1]
    src = IO.read(fn)
    define_method(:"test_sourcifier_prism_#{name}") {
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
  class Rewriter
    def initialize(rewrite_block)
      @rewrite_block = rewrite_block
    end

    def method_missing(sym, n)= sym !~ /^visit_/ ? super(sym, n) : visit(n)

    def visit(n)
      n2 = @rewrite_block.(n)
      return n2 if n2 != n

      replacements = {}
      n.deconstruct_keys(nil).each do |k, v|
        if v.is_a?(Ruby::Prism::Node)
          res = visit(v)
          replacements[k] = res if (res != v)
        elsif v.is_a?(Array) && v[0].is_a?(Ruby::Prism::Node)
          v2 = v.map { visit(it) }
          replacements[k] = v2 if v2 != v
        end
      end
      replacements.empty? ? n : n.copy(**replacements)
    end
  end

  def rewrite(ast, **replacements, &block)
    block ||= ->(n) { replacements.has_key?(n) ? replacements[n] : n }
    ast.accept(Rewriter.new(block))
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

  E4_LINE = __LINE__ + 2
  L4 = ->(x) {
    x == 2 ? (foo) : (bar)
  }

  def inlined_lambda(l)
    ast1 = Steadfast.to_ast(l)
    ast2 = rewrite(ast1) do |n|
      case n
      in Ruby::Prism::CallNode(receiver: nil, name: :foo)
        Steadfast.to_ast(L2).body.body[0]
      in Ruby::Prism::CallNode(receiver: nil, name: :bar)
        Steadfast.to_ast(L3).body.body[0]
      else
        n
      end
    end
    @source_location = ["(inlined_lambda-#{SecureRandom.hex(4)})", __LINE__ + 1]
    src = Steadfast.to_source(ast2, source_location: @source_location, sourcemap: true)
    eval(src, binding, *@source_location)
  end

  def test_sourcemap_inlined_lambda
    l = inlined_lambda(L1)
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

  def test_sourcemap_inlined_lambda_exception_backtrace
    l = inlined_lambda(L1)

    e = catch_error { l.(1) }
    assert_kind_of E1, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E1_LINE, line

    e = catch_error { l.(2) }
    assert_kind_of E2, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E2_LINE, line

    e = catch_error { l.(3) }
    assert_kind_of E3, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E3_LINE, line
  end

  def test_sourcemap_rewritten_single_line_lambda_exception_backtrace
    l = inlined_lambda(L4)

    e = catch_error { l.(2) }
    assert_kind_of E2, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E2_LINE, line

    e = catch_error { l.(3) }
    assert_kind_of E3, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E3_LINE, line
  end

  E5_LINE = __LINE__ + 1
  L5 = -> { raise E2, "E2" }

  E6_LINE = __LINE__ + 2
  L6 = -> {
    raise E3, "E3"
  }
  def inlined_lambda_without_inlined_filenames(l)
    ast1 = Steadfast.to_ast(l)
    ast2 = rewrite(ast1) do |n|
      case n
      in Ruby::Prism::CallNode(receiver: nil, name: :foo)
        L5.syntax_tree.body.body[0]
      in Ruby::Prism::CallNode(receiver: nil, name: :bar)
        L6.syntax_tree.body.body[0]
      else
        n
      end
    end
    @source_location = ["(inlined_lambda-#{SecureRandom.hex(4)})", 1]
    src = Steadfast.to_source(ast2, source_location: @source_location, sourcemap: true)
    # DEBUG:
    # puts
    # src.lines.each_with_index { |l, i| puts format('%2d %s', i + 1, l) }
    # puts
    # pp Steadfast.sourcemap
    # puts
    # p l5_filename: L5.syntax_tree.send(:source).__filename__
    eval(src, binding, *@source_location)
  end

  def test_sourcemap_inlined_lambda_without_inlined_filenames_exception_backtrace
    l = inlined_lambda_without_inlined_filenames(L1)

    e = catch_error { l.(1) }
    assert_kind_of E1, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E1_LINE, line

    e = catch_error { l.(2) }
    assert_kind_of E2, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E1_LINE + 1, line

    e = catch_error { l.(3) }
    assert_kind_of E3, e
    bt = Steadfast::SourceMapping.translate_backtrace(e.backtrace)
    filename, line = bt_entry_location(bt.first)
    assert_equal __FILE__, filename
    assert_equal E1_LINE + 3, line
  end
end

class SourcifierPrePostExecutionNodeTest < Minitest::Test
  def test_pre_execution_node
    n = Steadfast.make_node("BEGIN {\nfoo\n}")
    assert_equal "BEGIN {\nfoo\n}", Steadfast.to_source(n)
  end

  def test_post_execution_node
    n = Steadfast.make_node("END {\nfoo\n}")
    assert_equal "END {\nfoo\n}", Steadfast.to_source(n)
  end
end