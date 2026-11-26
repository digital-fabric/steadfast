# frozen_string_literal

require 'bundler/inline'

gemfile do
  source 'https://gem.coop'
  gem 'steadfast', path: '..'
end

require 'steadfast'
require 'benchmark/ips'

include Steadfast::Quote

def source_location(node)
  [(node.send(:source).__filename__ || raise('No filename set')), node.location.start_line]
end

def make_loop(*statements)
  loop_node = Steadfast.make_node("loop do; 1; end")
  loop_block_body = loop_node.block.body
  Steadfast.rewrite(loop_node, loop_block_body => { body: statements })
end

def convert_tail_call(tail, params)
  lvars = [*params.requireds.map(&:name), *params.optionals.map(&:name)]
  values = tail.arguments.arguments

  ast = Steadfast.make_node("#{lvars.join(', ')} = [nil]", location: tail)
  ast2 = Steadfast.rewrite(ast, ast.value => { elements: values })
end

def rewrite_with_tail_call(meth)
  ast = Steadfast.to_ast(meth)
  params = ast.parameters
  *body, tail = ast.body.body

  raise "Not a tail call method!" if !(tail.is_a?(Ruby::Prism::CallNode) && tail.name == meth.name)

  body2 = make_loop(*body, convert_tail_call(tail, params))
  ast2 = Steadfast.rewrite(ast, ast.body => { body: [body2] })
  Steadfast.eval_ast(ast2, meth.receiver)
end

def orig_fact(n, acc = 1)
  return acc if n <= 1
  orig_fact(n - 1, n * acc)
end

def tco_fact(n, acc = 1)
  return acc if n <= 1
  tco_fact(n - 1, n * acc)
end

rewrite_with_tail_call(method(:tco_fact))

puts "original fact(100000): #{begin; orig_fact(100000); rescue SystemStackError; 'failed'; end}"
puts "     TCO fact(100000): #{tco_fact(100000)}"
