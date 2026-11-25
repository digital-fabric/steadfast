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

Steadfast requires Ruby 4.0 or newer.

## Basic Usage

- Use `Steadfast.to_ast` to get the AST of a proc or a method.
- Rewrite (modify) an AST using `Steadfast.rewrite`.
- Build an AST using `Steadfast.quote` and `Steadfast.unquote`.
- Evaluate an AST using `Steadfast.eval_ast`.

```ruby
require 'steadfast'

l = -> { 42 }
msg = 'Hello'

ast = Steadfast.to_ast(l)
ast2 = Steadfast.rewrite(ast) do |n|
  next n if !(n in Ruby::Prism::IntegerNode(value: 42))

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
  (n in Ruby::Prism::CallNode(name: :foo)) ? Steadfast.quote { bar() } : n
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
    Steadfast.rewrite(replace_node, &block)
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

To be continued...