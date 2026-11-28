# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'steadfast'
require 'syntax_tree'

FIXTURES_PATH = File.join(__dir__, 'fixtures')

module Kernel
  def load_code(name)
    fn = File.join(EXAMPLES_PATH, "#{name}.rb")
    eval(IO.read(fn), binding, fn)
  end
end

class Minitest::Test
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
end

module Minitest::Assertions
  def assert_source_match exp, act
    exp = format_src(exp)
    act = format_src(act)

    msg = message(msg) { "Expected: \n\n #{act} \n\n to equal: \n\n #{exp}" }
    assert_equal exp, act, msg
  end

  private

  def format_src(src)
    SyntaxTree.format(src).gsub(/\n{2,}/m, "\n")
  rescue SyntaxTree::Parser::ParseError => e
    puts '*' * 40
    puts e.message
    puts e.backtrace.join("\n")
    puts src
    exit!(1)
  end
end
