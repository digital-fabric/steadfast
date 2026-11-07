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

module Minitest::Assertions
  def assert_source_match exp, act
    exp = format_src(exp)
    act = format_src(act)

    msg = message(msg) { "Expected: \n\n #{mu_pp(act)} \n\n to equal: \n\n #{mu_pp(exp)}" }
    assert_equal exp, act, msg
  end

  private

  def format_src(src)
    SyntaxTree.format(src).gsub(/\n{2,}/m, "\n")
  end
end
