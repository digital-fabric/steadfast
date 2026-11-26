<h1 align="center">
  <br>
  Steadfast
</h1>

<h4 align="center">A Metaprogramming Gem for Ruby</h4>

<p align="center">
  <a href="http://rubygems.org/gems/steadfast">
    <img src="https://badge.fury.io/rb/steadfast.svg" alt="Ruby gem">
  </a>
  <a href="https://github.com/digital-fabric/steadfast/actions">
    <img src="https://github.com/digital-fabric/steadfast/actions/workflows/test.yml/badge.svg" alt="Tests">
  </a>
  <a href="https://github.com/digital-fabric/steadfast/blob/master/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License">
  </a>
</p>

<p align="center">
  <img src="./steadfast.png">
</p>

Steadfast is a gem for working with Ruby [Prism](https://github.com/ruby/prism/)
[ASTs](https://en.wikipedia.org/wiki/Abstract_syntax_tree). Steadfast provides a
convenient, rich API for generating and transforming ASTs.

## Features

- Convert any proc or method to AST, convert any AST to source code.
- Rewrite, transform, compose and take apart ASTs.
- Comprehensive set of tools for creating synthetic AST nodes.
- Code quoting and templating using quote / unquote.
- Partial evaluation / specialization.
- Additional tools for iterating over ASTs and finding nodes.

## Requirements

Steadfast requires Ruby 4.1 or newer.

## Getting Started

Steadfast provides a variety of tools for working with ASTs. Here are the main
ones:

- `Steadfast.to_ast` - used to get the AST of a proc or a method.
- `Steadfast.rewrite` - used to create modified copies of ASTs.
- `Steadfast.quote` and `Steadfast.unquote` - used to generate ASTs and create
  code templates.
- `Steadfast.eval_ast` - used to evaluate ASTs.

In the following example, we'll take a lambda that returns an integer, extract
its AST, and modify it to return an interpolated string instead.

```ruby
require 'steadfast'

l = -> { 42 }
ast = Steadfast.to_ast(l)

msg = 'Hello'
ast2 = Steadfast.rewrite(ast) do |n|
  next n if !(n in Ruby::Prism::IntegerNode(value: 42))

  # Inject the value of a local variable into the string
  Steadfast.quote(binding) { "#{unquote(msg)} from Steadfast!" }
end

l2 = Steadfast.eval_ast(ast2)
l2.() #=> "Hello from Steadfast!"
```

## Rewriting ASTs

The `Steadfast.rewrite` method is a general-purpose tool for modifying ASTs.
Since Prism ASTs are immutable, `Steadfast.rewrite` lets you modify an AST by
creating a copy of it with the requisite node replacements. You can replace
nodes by providing a hash with the replacements to be made. For example:

```ruby
ast = Steadfast.to_ast(->() { foo() })
call_node = Steadfast.find(ast) { n in Ruby::Prism::CallNode(name: :foo)) }

# replace foo call with bar call
ast2 = Steadfast.rewrite(ast, call_node => quote { bar() })
```

Another way to use Steadfast.rewrite is by providing a block that will be
invoked for each node in the AST. The block should return eith the node passed
to it, or a replacement node if it should be replaced. For example:

```ruby
ast = Steadfast.to_ast(->() { foo() })

# replace foo call with bar call
ast2 = Steadfast.rewrite(ast) { |n|
  # use next to allow the iteration to continue
  next n if !(n in Ruby::Prism::CallNode(name: :foo))
 
  Steadfast.quote { bar() }
}
```

### Recursive rewriting

When using the block form of `Steadfast.rewrite`, if a block returns a
replacement node, it will not be iterated on. In order to allow recursive
processing of replacement nodes, `Steadfast.rewrite` provides the block with a
reference to itself, as a block argument, which you can use to make recursive
calls to `Steadfast.rewrite`:

```ruby
Steadfast.rewrite(ast) { |node, &block|
  if (replacement = should_replace_node?(node))
    Steadfast.rewrite(replacement, &block)
  else
    node
  end
}
```

## Code Quoting and Templating

Steadfast provides a quote / unquote mechanism similar to that found in
languages such as Elixir or Lisp, to facilitate code generation and code
templating.

`Steadfast.quote` is used to quote code, returning an AST for the code block
provided to it:

```ruby
Steadfast.quote(binding) { 42 } #=> IntegerNode
Steadfast.quote(binding) { foo(42) } #=> CallNode
Steadfast.quote(binding) { -> { 42 } } #=> LambdaNode
Steadfast.quote(binding) { foo; bar } #=> StatementsNode
```

`Steadfast.unquote` is used to convert a literal value into an AST. Normally, it
is used inside a `quote` block in order to inject the result of an expression or
block. The `unquote` call lets you inject arbitrary values into the quoted code:

```ruby
foo = 42
Steadfast.quote(binding) { x + unquote(foo) } #=> x + 42
```

## Creating Nodes

The easiest way to create new AST nodes is by using `Steadfast.quote`, as
explained above. Literal values can also be created using `Steadfast.unquote`:

```ruby
Steadfast.unquote({ foo: 1, bar: 2 })
```

Arbitrary types of nodescan be created by using `Steadfast.make_node` and
providing a string containing Ruby syntax:

```ruby
Steadfast.make_node('foo.bar(:baz)') #=> CallNode
```

The `Steadfast.make_node` method takes the following optional arguments:

- `location`: a Prism node or Prism location which will be used as the location
  for the generated AST.
- `lvars`: an array containing local variable names used in the given code
  snippet.
- `binding`: a binding for determining local variable names used in the given
  code snippet.

In addition to `Steadfast.make_node`, additional methods allow the creation of
specific node types:

- `Steadfast.make_call(name:, receiver:, args:)` - create a call node.
- `Steadfast.make_def(name:, params:, :body)` - create a method definition.

## Traversing ASTs and Finding Nodes

Use `Steadfast.walk` to visit each node in an AST:

```ruby
Steadfast.walk(ast) { p it } #=> print out each node in the AST
```

To find a node, use `Steadfast.find`. This method will return the first node for
which the given block returns true, or nil if none found:

```ruby
# look for a call to foo
Steadfast.find(ast) { n in Ruby::CallNode(receiver: nil, name: :foo) }
```

To find all nodes that respond to specific criteria, use `Steadfast.find_all`:

```ruby
# find all method calls without a receiver
Steadfast.find_all(ast) { n in Ruby::CallNode(receiver: nil) }
```

## AST Conversion and Evaluation

Additional Steadfast allow you to convert a method or proc to AST, to convert an
AST to source code, and to evaluate ASTs. To get the AST for a proc or method,
use `Steadfast.to_ast`:

```ruby
def foo
  42
end

foo_ast = Steadfast.to_ast(method(:foo))
```

To convert an AST to source code, use `Steadfast.to_source`:

```ruby
Steadfast.to_source(foo_ast) #=> "def foo..."
```

To evaluate an AST use `Steadfast.eval_ast`:

```ruby
ast = quote { puts 'Hi!' }
Steadfast.eval_ast(ast) #=> 'Hi!!!'
```
