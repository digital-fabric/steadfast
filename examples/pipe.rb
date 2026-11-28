# frozen_string_literal

require 'bundler/inline'

gemfile do
  source 'https://gem.coop'
  gem 'steadfast', path: '..'
end

require 'steadfast'

include Steadfast::Quote

def add(x, y); x + y; end
def mul(x, y); x * y; end
def pow(x, y); x ** y; end

def compute_with(x)
  pipe { x >> add(3) >> mul(6) >> pow(2) }
end

def convert_pipe_expression(ast)
  Steadfast.rewrite(ast) { |n, &b|
    next n if !(n in Ruby::Prism::CallNode(name: :>>))

    call_node = n.arguments.arguments[0]
    next n if !n in Ruby::Prism::CallNode

    arguments = [Steadfast.rewrite(n.receiver, &b), call_node.arguments]
    Steadfast.rewrite(call_node, call_node.arguments => { arguments: })
  }
end

# @param meth [Method]
def rewrite_pipe(meth)
  ast = Steadfast.to_ast(meth)
  ast2 = Steadfast.rewrite(ast) { |n|
    next n if !(n in Ruby::Prism::CallNode(receiver: nil, name: :pipe))

    converted = convert_pipe_expression(n)
    converted.block.body
  }
  puts Steadfast.to_source(ast2)
  puts
  Steadfast.eval_ast(ast2, meth.receiver)
end

rewrite_pipe(method(:compute_with))

p result: compute_with(42)