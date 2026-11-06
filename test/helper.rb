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
    exp = SyntaxTree.format(exp)
    act = SyntaxTree.format(act)
    
    msg = message(msg) { "Expected #{mu_pp(act)} to be in range #{mu_pp(exp_range)}" }
    assert_equal exp, act, msg
  end
end
