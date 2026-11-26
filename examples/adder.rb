# frozen_string_literal

require 'bundler/inline'

gemfile do
  source 'https://gem.coop'
  gem 'steadfast', path: '..'
end

include Steadfast::Quote

def make_adder(v)
  ast = quote(binding) { ->(x) { x + unquote(v) } }
  Steadfast.eval_ast(ast)
end

adder = make_adder(2)
puts "2 + 3 = #{adder.(3)}"
