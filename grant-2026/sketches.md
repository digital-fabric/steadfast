## Simple

```ruby
# inline lambda generation
def make_adder(v)
  ->(x) { x + v }
end

# string interpolation
def make_adder(v)
  eval("->(x) { x + #{v.inspect} }")
end

# quote/unquote
def make_adder(v)
  ast = quote { ->(x) { x + unquote(v) } }
  eval(ast.to_source)
end
```

## Validator

An example of how such a mechanism may be used, here's how we may define a
general-purpose argument validator:

```ruby
# inline lambda generation
def create_validator(*conds)
  ->(v) {
    conds.each { raise unless it === v }
    v
  }
end

# string interpolation
def create_validator(*conds)
  code = <<~RUBY
    ->(v) {
      #{conds.map { "raise unless (#{it.inspect}) === v;" }.join}
    }
  RUBY
  eval(code)
end

# quote/unquote
def create_validator(*conds)
  # quote returns an AST
  ast = quote {
    ->(v) {
      unquote conds.map { |c| quote { unquote(c) === v } }
      v
    }
  }
  eval(ast.to_source)
end
```

## Papercraft template compiler

```ruby
# source:
t = ->(foo) {
  div {
    if foo
      h1 'foo'
    else
      h2 'bar'
    end
  }
}

# compiled:
->(__buffer__, foo) {
  __buffer__.<<("<div>")
  if foo
    __buffer__.<<("<h1>foo</h1>")
  else
    __buffer__.<<("<h2>bar</h2>")
  end
  __buffer__.<<("</div>")
  __buffer__
}
```

We need to generate a lambda, which we do with #make_lambda, because we need to
prepend the __buffer__ param to the list of lambda params. The body of the
lambda is compiled from the given template AST with compile_html.

```ruby
# @param template [Proc] original template
# @return [Proc] compiled template
def compile(template)
  ast = Sirop.ast(template)
  compiled = Sirop.make_lambda(
    parameters: [:__buffer__, *ast.parameters],
    body: compile_html(ast)
  }
  eval(Sirop.to_source(compiled))
end
```

This is the hard part - how to "mutate" the original AST into the compiled form.
We could do this using a MutationVisitor, which is similar to the current
implementation of Papercraft, but what would be interesting is to see if we can
do this using some kind of DSL that allows us to visit each node in the AST and
either emit it or emit some specialized code:

```ruby
# @param ast [Prism::Node] template body ast
# @return [Prism::Node] compiled ast
def compile_html(ast)
  html_parts = []
  flusher = -> {
    return nil if html_parts.empty?

    html = html_parts.join; html_parts.clear
    quote(locals: [:__buffer__]) { __buffer__ << unquote(html) }
  }
  quote(locals: [:__buffer__, *ast.parameters]) {
    unquote(
      ast_transform(ast) { |node, transform|
        if html_tag?(node)
          emit_html(node, transform, html_parts, flusher)
        else
          [flusher.(), *transform.(node)]
        end
      }
    )
    unquote(flusher.() || :__nop__)
    __buffer__
  }
end

def html_tag?(node)
  node.is_a?(Prism::CallNode) && node.receiver.nil? && other_conditions(node)
end

def emit_html(node, transform, html_parts, flusher)
  if node.block?
    emit_html_with_block(node, transform, html_parts, flusher)
  else
    html_parts << format_html_tag(node)
  end
end

def emit_html_with_block(node, transform, html_parts, flusher)
  html_parts << format_html_open_tag(node)
  ast = transform.(node.block)
  html_parts << format_html_close_tag(node)
  ast
end
```

How does quote work?

```ruby
def quote(**opts, &block)
  ast = Sirop.ast(block)

  # the quote_transform will mutate the ast such that any call to unquote inside
  # the block will be replaced with the result of the actual unquote call
  ast_transform(ast, **opts) { |node, transform|
    if unquote_call?(node)
      unquote_value_to_ast(node.parameters[0], transform)
    else
      node
    end
  }
end
```

How does unquote work?

```ruby
# @param v [any] value
# @return [Prism::Node] AST node
def unquote(v)
  case v
  when nil, Prism::Node
    v # if nil is returned, nothing is emitted into the quote block
  else
    to_ast(v)
  end
end

def to_ast(v)
  case v
  when nil
    Prism::NilNode.new(...)
  when true
    Prism::TrueNode.new(...)
  when Integer
    Prism::IntegerNode.new(...)
  # etc...
  end
end
```

Additional tools required:

```ruby
def ast_transform(ast, &block)
  transform = ->(node) { block.(node, transform) }
  block.(ast, transform)
end
```

## ERB compiler

Can we implement an ERB compiler with quote/unquote?

```ruby
TEMPLATE = <<~ERB
  <ul>
    <% @items.each do |i| %>
      <li><%= i %></li>
    <% end %>
  </ul>
ERB

# compiled proc looks like:
-> {
  __buffer__ = +'<ul>'
  @items.each do |i|
    __buffer << "<li>#{i}</li>"
  end
  __buffer << '</ul>'
  __buffer__
}

# @param template [String]
# @return [Proc]
def compile_erb(template)
  parts = TEMPLATE.split(/(\<%\=?.+)%\>/).map(&:strip)
  ast = quote {
    __buffer__ = +''
    unquote(
      parts.map do |p|
        case p
        when m = p.match(/\<%\= (.+)/)
          quote { __buffer__ << "#{unquote_verbatim(m[1])}" }
        when m = p.match(/\<% (.+)/)
          quote { unquote_verbatim(m[1]) }
        else
          quote { __buffer__ << unquote(p) }
        end
      end
    )
    __buffer__
  }
  eval(Sirop.to_source(ast))
end
```

This is a very simple compiler, not at all optimized, but it shows how this
could be done. If we want to buffer html parts and then flush them into
`__buffer__ << ...` expressions, we'll need to employ the technique shown above
for the Papercraft compiler, but this is totally doable.

Additional tools:

```ruby
def unquote_verbatim(str)
  # this could be a bit more complicated, if we need to take into account local vars etc.
  magically_convert_string_to_ast(str)
end
```

## Something like has_many

The Rails implementation of `has_many` is amazingly complex! But finally, it
does get down to a bunch of `eval`s, or rather, `class_eval`:

```ruby
# https://github.com/rails/rails/blob/c9e85dbe297e248dd2f217d04f84a94881ac046a/activerecord/lib/active_record/associations/builder/association.rb#L103
def self.define_readers(mixin, name)
  mixin.class_eval <<-CODE, __FILE__, __LINE__ + 1
    def #{name}
      association = association(:#{name})
      deprecated_associations_api_guard(association, __method__)
      association.reader
    end
  CODE
end
```

We need a way to define a method:

```ruby
def define_readers(mixin, name)
  ast = Sirop.make_method(
    name: name,
    parameters: [],
    body: quote {
      association = association(unquote(name))
      deprecated_associations_api_guard(association, __method__)
      association.reader
    }
  )
  mixin.class_eval(Sirop.to_source(ast))
end
```

Actually, Ruby syntax allows us to do the following:

```ruby
def define_readers(mixin, name)
  ast = quote {
    def unquote(name)
      association = association(unquote(name))
      deprecated_associations_api_guard(association, __method__)
      association.reader
    end
  }
  mixin.class_eval(Sirop.to_source(ast))
end
```

While the syntax is a bit confusing, this is exactly how it looks in Elixir:

```elixir
defmacro define_function(name, return_value) do
  # Ensure the name is an atom (e.g., :my_func)
  func_name = String.to_atom("#{name}")

  quote do
    # Unquote `func_name` inside the function header
    def unquote(func_name)() do
      unquote(return_value)
    end
  end
end
```

## Can we do the same for a lambda definition?

Suppose we want to create a lambda with arbitrary parameters (e.g. the
Papercraft compiler):

```ruby
quote {
  ->(__buffer__, unquote(ast.parameters)) { 42 }
}
```

While Prism does parse this, the whole AST looks bizarre and quite distorted,
which may lead to all kinds of problems when trying to transform it back to
source code. We might want to experiment with this, but on the whole, this may
lead to unforseen problems and limitations, and may also significantly
complicate the implementation.

Let's put this aside for the moment, and concentrate on providing simpler tools for defining methods and lambdas:

```ruby
quote {
  def_method(unquote(name), a, b, *, **, &) {
    ...
  }

  def_lambda(__buffer__, unquote(ast.arguments)) {
    ...
  }
}
```

Yeah, that's much clearer, and also simpler to implement.

## Interim summary 1

So, we have the following tools:

- `quote { ... }` (convert given block to ast)
- `unquote(v)` (convert arbitrary value to ast (inside quote))
- `ast_transform(ast) { |node, transformer| ... }` (deep transform ast)

- `unquote_verbatim(str)` (convert given source code to ast)
- `def_method(unquote(name), *params) { ... }` (define method)
- `def_lambda(*params) { ... }` (define lambda)

## What about source locations?

One simple option is to synthesize the AST and also synthesize the location info
of the macro definition:

```ruby
# adder.rb:
def make_adder(v)
  ast = quote {
    ->(x) {
      x + unquote(v)
    }
  }
  eval(ast.to_source, *ast.source_location)
end

adder = make_adder(1)
adder(:a)
#=> BOOM: undefined method '+' ...
# from adder.rb:4:in ...
# from adder.rb:11:in '<main>'
```

At least for a beginning, this should work fine. Eventually, we might want to
cache "rendered" source code with synthetic source locations such as
`(:adder:foo):1', which we might express with:

```ruby
ast = quote(key: 'adder:foo') { ... }
```

## More on the Behaviour of unquote

### unquote(nil)

The above `unquote` implementation behaviour when passed a `nil` is problematic.
We need to be able to inject a nil into the quoted code.

### unquote([...].map { ... })

When calling unquote with an array, we also need to differentiate between an
array of normal values and an array of AST nodes, like in the validator example
above. We can be more explicit about it by providing another tool, e.g.:

```ruby
# implicit (same as validator example above)
def create_validator(*conds)
  # quote returns an AST
  ast = quote {
    ->(v) {
      unquote(
        conds.map { |c| quote { unquote(c) === v } }
      )
      v
    }
  }
  eval(ast.to_source)
end

# explicit
def create_validator(*conds)
  # quote returns an AST
  ast = quote {
    ->(v) {
      unquote_block(
        conds.map { |c| quote { unquote(c) === v } }
      )
      v
    }
  }
  eval(ast.to_source)
end
```

## Interim summary 2

So, we have the following tools:

- `quote { ... }` (convert given block to ast)
- `unquote(v)` (convert arbitrary value to ast (inside quote))
- `ast_transform(ast) { |node, transformer| ... }` (deep transform ast)

- `unquote_verbatim(str)` (convert given source code to ast)
- `unquote_block([...])` (convert given array of nodes to a block node) (???)
- `def_method(unquote(name), *params) { ... }` (define method)
- `def_lambda(*params) { ... }` (define lambda)

## Deep transform of a block (Test example)

Suppose we want to define a test DSL:

```ruby
# taking inspiration from https://zig.guide/getting-started/running-tests/

require 'footest'

test 'always succeeds' {
  expect(true)
}

test 'always fails' {
  expect(false)
}

test 'expression' {
  expect(1  + 1 != 2)
}

# expect an exception
test 'raise' {
  expect_raises(NoMethodError, foo.bar)
}

# regexp
test 'raise' {
  expect 'foobar' =~ /baz/
  expect (m = 'foo'.match(/f(.+)/)) && m[1] == 'oo'
}

# custom expect
```

With this syntax, we can avoid implementing expect with a block. Instead We need
to intercept the calls to `expect` as follows:

```ruby
def test(name, &block)
  ast = Sirop.ast(block)
  transformed = mutate(ast) { |node, transform|
    if node in Prism::CallNode, receiver: nil, name: :expect, arguments:)
      quote { assert { unquote(arguments[0]) } }
    else
      transform.(node)
    end
  }
  test_case = Testing::TestCase.new(name, eval_ast(transformed))
end
```

So here we add an `ast_match` Gtool for matching a node by type and by arbitrary
properties, but we can also use pattern matching, which Prism already supports:

```ruby
ast_transform(ast) { |node, transform|
  case node
  in Prism::CallNode(receiver: nil, name: :expect, arguments: [expr, *])
    quote { test.assert { unquote(node.arguments[0]) } }
  else
    transform.(node)
  end
}
```

So, actually no need to have our own tool, just use regular pattern matching.

## Generating code and saving it

Rails generators use ERB templates, here's an excerpt:

```erb
class <%= migration_class_name %> < ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]
  def change
    create_table :<%= table_name %><%= render_table_with_dom_id %> do |t|
<% attributes.each do |attribute| -%>
<% if attribute.password_digest? -%>
      t.string :password_digest<%= attribute.inject_options %>
<% elsif attribute.token? -%>
      t.string :<%= attribute.name %><%= attribute.inject_options %>
<% else -%>
      t.<%= attribute.type %> :<%= attribute.name %><%= attribute.inject_options %>
<% end -%>
<% end -%>
<% if options[:timestamps] -%>
      t.timestamps
<% end -%>
    end
  end
end
```

How would it look with quote/unquote?

```ruby
version = ActiveRecord::Migration.current_version
ast = quote do
  def_class(unquote(migration_class_name), ActiveRecord::Migration[unquote(version)]) do
    def change
      create table unquote(table_name) do |t|
        unquote attributes.map do |attribute|
          opts = attribute.inject_options
          if attribute.password_digest?
            quote { t.string unquote(:"password_digest#{opts}") }
          elsif attribute.token?
            quote { t.string unquote(:"#{attribute.name}#{opts}") }
          else
            # note use of unquote as method name
            quote { t.send(unquote(attribute.type), unquote(:"#{opts}") }
          end
        end
        unquote(
          options[:timestamps] ? quote { t.timestamps } : :__nop__
        )
      end
    end
  end
end

IO.write(fn, Sirop.to_source(ast))
```

## Class/module definitions

Actually, Prism does accept class definitions in the form:

```ruby
class unquote(c) < A::B::unquote(1)
  def x; 1; end
end
```

But it fucks up syntax highlighting, at least in Zed, so we'll probably want to
have `def_class` and `def_module`.

## The nil problem revisited

In order to allow `unquote` to emit nothing, we introduce the `:__nop__` value,
which lets us conditionally emit code. Quick recap: unquote is evaluated at
compile time, while the surrounding quoted code is evaluated at run time. So
unquote allows us to conditionally generate code. Using `:__nop__` allows us to
treat nil as a normal value.

```ruby
def gen(x, print)
  ast = quote {
    unquote(
      print ? quote { puts "Adding to #{unquote(x)}" } : :__nop__
    )
    x + 1
  }
end
```

## Interim summary 3

So, we have the following tools:

- `quote { ... }` (convert given block to ast)
- `unquote(v)` (convert arbitrary value to ast (inside quote))
- `ast_transform(ast) { |node, transformer| ... }` (deep transform ast)
- `:__nop__` special value for emitting nothing

- `unquote_verbatim(str)` (convert given source code to ast)
- `unquote_block([...])` (convert given array of nodes to a block node) (???)

- `def_class(class_name, base_class = nil) { ... }` (define class)
- `def_module(module_name) { ... }` (define module)
- `def_method(unquote(name), *params) { ... }` (define method)
- `def_lambda(*params) { ... }` (define lambda)

Remarks and observations:

- `unquote` is eavaluated at macro compile time, which lets us generate code
  conditionally.
- `unquote_block` can be used to transform any enumerable into a block of code.
  Here, too, we may use `:__nop__`:

  ```ruby
  quote {
    unquote_block items.map { |i|
      i.show? ? quote { t.send(unquote(i.to_sym), true) } : :__nop__
    }
  }
  ```

## unquoting a method call

In the above last example, we want to generate a method call based on some
unquoted value. We need a tool for doing this:

```ruby
quote {
  # instead of
  t.send(unquote(m), *, **, &)

  # do this
  t.__call__(unquote(m), *, **, &)
}
```

## Interim summary 4

So, we have the following tools:

- `quote { ... }` (convert given block to ast)
- `unquote(v)` (convert arbitrary value to ast (inside quote))
- `ast_transform(ast) { |node, transformer| ... }` (deep transform ast)
- `:__nop__` special value for emitting nothing

- `unquote_verbatim(str)` (convert given source code to ast)
- `unquote_block([...])` (convert given array of nodes to a block node) (???)

- `o.__call__(m, *, **, &)` (method call with arbitrary method name)
- `def_class(class_name, base_class = nil) { ... }` (define class)
- `def_module(module_name) { ... }` (define module)
- `def_method(unquote(name), ...) { ... }` (define method)
- `def_lambda(*params) { ... }` (define lambda)

Remarks and observations:

- `unquote` is eavaluated at macro compile time, which lets us generate code
  conditionally.
- `unquote_block` can be used to transform any enumerable into a block of code.
  Here, too, we may use `:__nop__`:

  ```ruby
  quote {
    unquote_block items.map { |i|
      i.show? ? quote { t.__call__(unquote(i.name), true) } : :__nop__
    }
  }
  ```

## Enhancing methods

Suppose we want to be able to automagically memoize arbitrary methods.

The traditional approach would be something like:

```ruby
# by defining a module (should work, but check it)
module Memoize
  def memoize(*methods)
    mod = Module.new
    methods.each do |m|
      mod.define_method(m) { (@memo ||= {})[m] ||= super }
    end
    prepend(mod)
  end
end
```

With quote/unqoute:

```ruby
module Memoize
  def memoize(*methods)
    methods.each do |m|
      ast = Sirop.to_ast(method(m))
      # in place mutation (can we make this work?)
      # Sirop.mutate(root, node => replacement, ...)
      memoized = Sirop.mutate(
        ast,
        ast.body => quote { (@memo ||= {})[m] = (unqoute(ast.body)) }
      )
      eval(Sirop.to_source(memoized))
    end
  end
end
```

## Mutating an AST

We introduce `#mutate` method which are used to do a deep transform.

```ruby
# mutate with a block
l1 = ->(x) { 42 }
l2 = Sirop.eval self, Sirop.mutate(Sirop.to_ast(l1)) { |n|
  n.is_a?(Prism::IntegerNode) ? quote { 43 } : n
}

# mutate with node replacement hash
ast = Sirop.to_ast(method(:foo))
Sirop.eval self, Sirop.mutate(
  ast, ast.body => quote {
    (@memo ||= {})[m] = (unqoute(ast.body))
  }
)
```

Added tools:

- `Sirop.eval(receiver, ast)` - eval the given ast on the given receiver
- `Sirop.mutate(ast) { ... }` - copy the ast, replacing nodes with the result of
  the block
- `Sirop.mutate(ast, n1 => n2)` - copy the ast, replacing nodes with given
  replacements

## RoutingTree

```ruby
# from routing_tree.rb
def emit_wildcard_childless_root_code(buffer, root_path)
  emit_code_line(buffer, '->(path, params) {')
  if root_path != '/'
    re = /^#{Regexp.escape(root_path)}(\/.*)?$/
    emit_code_line(buffer, "  return if path !~ #{re.inspect}")
  end
  emit_code_line(buffer, "  @dynamic_map[#{root_path.inspect}]")
  emit_code_line(buffer, '}')
end
```

What about:

```ruby
def emit_wildcard_childless_root_code(root_path)
  re = /^#{Regexp.escape(root_path)}(\/.*)?$/
  quote {
    ->(path, params) {
      unquote(
        root_path != '/' ?
          quote { return if path != unquote(re) }) : :__nop__
      )
      dynamic_map[unquote(root_path)]
    }
  }
end
```

Further on:

```ruby
def visit_routing_tree_entry(entry:, segment_idx:)
  # If no targets exist in the entry's subtree, we can return nil
  # immediately.
  if !entry[:target] && !find_target_in_subtree(entry)
    return quote { nil }
  end

  if void_route?(entry)
    parent = entry[:parent]
    parametric_sibling = parent && parent[:children] && parent[:children]['[]']
    if parametric_sibling
      return quote { nil }
    end
  end

  return :__nop__ if !entry[:target] && !entry[:children]

  if entry[:target] && entry[:handle_subtree] && !entry[:children]
    if entry[:static] ?
      quote { return @static_map[unquote(entry[:path])] } :
    else
      quote { return @dynamic_map[unquote(entry[:path])] }
    end
  end

  clauses = []
  if entry[:target]
    return_expr = entry[:static] ?
      quote { return @static_map[unquote(entry[:path])] } :
      quote { return @dynamic_map[unquote(entry[:path])] }
    clauses << quote { when nil; unquote(return_expr) }
  end
  if entry[:children]
    clauses << routing_tree_entry_children_clauses(clauses, entry:, segment_idx:)
  end

  # Get next segment
  if !clauses.empty?
    quote {
      case (s = segments[unquote(segment_idx)])
        unquote()
      end
    }
  end
end
```

There are two problems with this, related to how case is parsed. Prism cannot
parse an isolated "when foo" expression. It also can't parse "case x;
unquote(y); end", so we need a way to express this. Maybe:

```ruby
quote {
  __.case(foo) {
    __.when nil
      return nil
    __.else {
      __.case ...
    }
  }
}
```

OK, this looks OK for what it does. But can we take it further?

```ruby
quote {
  __.case(foo) {
    unquote clauses.map { quote {
      __.when(nil) {
        return nil
      }
    }}
    __.else
      unquote {
        if entry[:is_static]
          quote { __.return @static_map['/foo/bar'] }
        else
          quote { __.return @dynamic_map['/foo/bar'] }
        end
      }
  }
}
```

## The binding problem

We have a big problem:

```ruby
def unroll_loop(range, &block)
  quote {
    unquote {
      range.map { |v|
        quote { block.(unquote(v)) }
      }
    }
  }
end
```

The quoted block is not `eval`ed. The block given to unquote is reified from the
AST and then `eval`ed. The problem here is that when `eval`ing the unquoted
block, we don't have access to the binding of `unroll_loop`, since we're running
in the context of a `quote` call. This is the famous "binding of caller"
problem.

A solution would be to explicitly pass the binding to quote:

```ruby
quote(binding) { ... }
```

This allows us to do this, and the syntax cost is negligible. This is good
enough.

## Interim summary 5

Again, the basic tools:

- `quote(?binding) { }`
- `unquote(v)` / `unquote { }`
- `mutate(v)` / `mutate { }`

Source <-> AST:

- `Sirop.to_ast(o)`
- `Sirop.to_source(ast)`
- `eval_ast(ast)`

Synthetic code:

- `__.case(e) { }`/`__.when(e) { }`/`__.if(e) { }` etc.
- `__.def(m, *args) { }`
- `__.lambda(*args) { }`
- `__.(m, *args)` - a synthetic call
- `receiver.__.(m, *args)` - synthetic call with receiver
- `__.begin { }` / `__.rescue(E => e) { }` / `__.ensure { }` etc.

## Implementing something like `__.case`

```ruby
def synthetic_case(expr_ast, body_ast)
  # using the Prism DSL
  Prism::CaseNode(value: expr_ast, body: body_ast, ...)
end

# some are easier:
def synthetic_begin(body_ast)
  quote(binding) { begin { unquote(body_ast) } }
end
```

## The question of backtraces

Since we're generating a synthetic AST, which may be compose of ASTs originating
in different source locations, how can we reflect the true location of each part
of the generated code?

One solution is to just do what tools like ERB or IRB do, and report the
filename as `(sirop)`.

A second solution is to add a `begin/rescue` and translate the backtrace
accordingly, but this solution may prove to be brittle, and inexact.

## unquote outside of quote

We can use `Sirop.to_ast` to convert arbitrary values to AST:

```ruby
Sirop.to_ast(ast) #=> ast
Sirop.to_ast(1) #=> IntegerNode
Sirop.to_ast([ast1, ast2]) #=> StatementsNode
```

# 2026-10-15

## Solving the binding problem

It turns out `binding_of_caller` still exists. Looking at the code, it actually
uses `debug_inspector` behind the scenes. The forward compatibility story for
this gem is not clear, but it does work with Ruby 4.1:

```ruby
require 'debug_inspector'

def get_caller_binding(idx = 3)
  DebugInspector.open { # frame 2
    it.frame_binding(idx) #frame 1
  }
end
```

## Making it possible to evaluate an AST

This might be an interesting goal if the grant proposal is accepted:

```ruby
ast = quote { 1 + 2 }
eval(ast)
```

So, we make it so eval can accept an AST instead of a string.

Some questions:

- Is `Prism::Node` backed by the `pm_node` c struct, or is it Reified. In other
  words, given a (mutated) AST, is it backed by the corresponding c structs?
- How complicated would it be to follow the execution path through the Ruby
  code? At first look it seems quite convoluted, but needs closer scrutiny.
- Should this kind of contribution

## Some examples of code generation:

These examples code be used to demonstrate the power of quote/unquote by doing a
side-by-side comparison of the original code vs the quote/unquote driven one.

- Sequel - `Dataset.def_sql_method` - gradual construction of source code string

  https://github.com/jeremyevans/sequel/blob/b48f23e9ec3db3d8d5e6b2de925b4bf1c0d91c63/lib/sequel/dataset/sql.rb#L241

  ```ruby
  ...
  lines << 'private' if priv
  lines << "def #{'_' if priv}#{type}_sql"
  lines << 'if sql = opts[:sql]; return static_sql(sql) end' unless priv
  lines << "if sql = cache_get(:_#{type}_sql); return sql end" if cacheable
  lines << 'check_delete_allowed!' << 'check_not_limited!(:delete)' if type == :delete
  lines << 'sql = @opts[:append_sql] || sql_string_origin'
  ...
  ```

- Roda - `AllVerbs::RequestMethods` - simple example

  https://github.com/jeremyevans/roda/blob/22a712bef1e87bd5f8e17341bb21747b59348670/lib/roda/plugins/all_verbs.rb#L38

- ActiveRecord - `...::Builder::Association` - simple example

  https://github.com/rails/rails/blob/c9e85dbe297e248dd2f217d04f84a94881ac046a/activerecord/lib/active_record/associations/builder/association.rb#L103

- Memoist - a bit more complex

  https://github.com/matthewrudy/memoist/blob/master/lib/memoist.rb#L163

- Minitest - a bit more complex

  https://github.com/minitest/minitest/blob/581e7d5386def72040e49b036ba49e36e9cb14df/lib/minitest/spec.rb#L8

- ActiveSupport - very complex example (spaghetti level!)

  https://github.com/rails/rails/blob/85dbd088e8dc7338cb80c4d672d0fd1781e0f410/activesupport/lib/active_support/delegation.rb#L152

# 2026-10-26

## method definition with __.def - where are the limits?

How can we express default values for regular arguments?

```ruby
# https://github.com/lostisland/faraday/blob/670f3a6aef13734841e926f991cbb1c47bc3c5ee/lib/faraday/connection.rb#L198

quote {
  # how can we do this?
  __.def(unquote(method), url = nil, params = nil, headers = nil) do
    ...
  end
}
```

## call syntax with unquote

One possibility is doing a `__.call(meth)` or even `receiver.__.call(method)`.

Another possibility is doing `__.unquote(meth)` (maybe as shorthand)

# 2026-10-29 Alternatives to the double underscore syntax

For expressing stuff like `rescue`, `def` etc.

```ruby
__.def(...) { }
$$.def(...) { }
$_.def(...) { }
§.def(...) { }
```

# 2026-11-02

## Tail call to loop

We have a recursive function:

```ruby
def fact(n, acc = 1)
  return acc if n <= 1
  fact(n - 1, n * acc) # <-- Tail position (last operation)
end
```

We can rewrite this to something like:

```ruby
def fact(n, acc = 1)
  loop do
    return acc if n <= 1
    n, acc = [n - 1, n * acc]
  end
end
```

How do we do this?

```ruby
# @param meth [Method]
def rewrite_with_tail_call(meth)
  ast = meth.syntax_tree

  params = ast.parameters
  *body, tail = ast.body.body

  raise "Not a tail call method!" if !(tail.is_a?(Prism::CallNode) && tail.name == meth.name)

  ast2 = quote {
    __.def(unquote(meth.name), unquote(params)) do
      loop {
        unquote(body)
        unquote(convert_tail_call(tail, params))
      }
    end
  }
  meth.receiver.instance_eval(Sirop.to_source(ast2))
end

# @param tail [Prism::Node]
# @param params [Prism::Node]
def convert_tail_call(tail, params)
  arg_count = 0
  quote {
    # __.assign(left, right), in this case we assign
    __.assign(
      unquote([*params.requireds.map(&:name), *params.optionals.map(&:name)]),
      unquote(tail.arguments.arguments)
    )
  }
end
```

Yeah, doable, but not very pretty, not very readable, not very practical for
less-experienced developers.

## Parametric local vars

```ruby
# from the above example:
__.assign(x, y) #=> x = y
__.var(x) #=> x

# but we can also do:
__.local[x] = y

# and following this pattern:
__.ivar[x] = y
__.cvar[x] = y
```

Yeah, this looks like a better approach.

What if we want to synthesize something like:

```ruby
x.y.z[:foo] = :bar
```

We can do:

```ruby
__.call(:x).__.call(:y).__.call(:z)[:foo] = :bar
```

Also, something we need to take into account is the difference between method
calls and local vars, which may not matter for converting an AST to source code,
but *will* matter when calling `eval`. Here, again, is where the `binding`
becomes crucial.

## Another tail-call method, Fibonnaci:

```ruby
def fib(n, a = 0, b = 1)
  return a if n == 0
  fib(n - 1, b, a + b) # <-- Tail position (last operation)
end
```

Converted:

```ruby
def fib(n, a = 0, b = 1)
  loop {
    return a if n == 0
    n, a, b = [n - 1, b, a + b]
  }
end
```

# 2026-11-04

## Dynamically Generated Keywords

Previously, we looked at how we can generate custom syntax parts using e.g.
`__.def`, `__.rescue` etc. Looking at how this is done in Elixir (`unquote({:do,
do_target})`), we can imagine something similar for our tool:

Original version:

```ruby
quote {
  __.case(foo) {
    unquote clauses.map { quote {
      __.when(nil) {
        return nil
      }
    }}
    __.else
      unquote {
        if entry[:is_static]
          quote { __.return @static_map['/foo/bar'] }
        else
          quote { __.return @dynamic_map['/foo/bar'] }
        end
      }
  }
}
```

New syntax:

```ruby
quote {
  unquote(:case, foo) {
    unquote clauses.map { quote {
      unquote(:when, nil) {
        return nil
      }
    }}
    unquote(:else) {
      unquote {
        if entry[:is_static]
          quote { unquote(:return, @static_map['/foo/bar']) }
        else
          quote { unquote(:return, @dynamic_map['/foo/bar']) }
        end
      }
    }
  }
}
```

I don't like it. What about:

```ruby
quote {
  §case(foo) {
    unquote clauses.map { quote {
      §when(nil) {
        return nil
      }
    }}
    §else
      unquote {
        if entry[:is_static]
          quote { §return @static_map['/foo/bar'] }
        else
          quote { §return @dynamic_map['/foo/bar'] }
        end
      }
  }
}
```

This could work, but the problem is that § is not available on all keyboards.
But finally we can use any number of variations on the basic idea of expressing
those keywords as method calls: `$$.def(...) { ... }`, `!.def(...) { ... }` etc.

# 2026-11-10

## Inlining method / lambda calls

For use in Papercraft, but might be interesting for other uses?

```ruby
layout = ->(**, &) {
  html {
    body {
      header 'Header'
      main(**, &)
    }
  }
}

page = Papercraft.render(layout, bar: 42) { |bar:, **|
  h2 'foo'
  p "bar: #{bar}"
}
```

Which should be expanded to:

```ruby
->(**__kwargs__, &) {
  html {
    body {
      header 'Header'
      main {
        h2 'foo'
        p "bar: #{__kwargs__[:bar]}"
      }
    }
  }
}
```

With mutate, composing the two ASTs is easy. The hard part is coming up with an algorithm to rewrite the argument names:

- Anonymous rest args/kwargs should be rewritten to named rest args/kwargs
- local var assignments in the inlined AST should also be renamed, such that no value gets accidentally overwritten

How would the API for this look?

```ruby
Steadfast.inline_ast(layout_ast) { |n|
  # this block is invoked for each CallNode or a
  # anonymous BlockArgumentNode (where expression is nil)

  # the block is expected to either return an AST, which will be inlined (with
  # arguments and local vars rewritten)
  # If nil is returned, nothing is inlined
}
```

We can also design a separate APIs for getting and rewriting local vars and
args:

```ruby
Steadfast.local_vars(ast) #=> returns a list of var names

Steadfast.rewrite_local_vars(ast, **substitutions) #=> returns a mutated AST with substituted var/arg names
```

## Another example

```ruby
l1 = ->(a, b) {
  div {
    foo(a, b, 42)
  }
}

l2 = ->(x, y, z) {
  p {
    yy = y + 2
    bar(x, yy, z + 3)
  }
}

Steadfast.inline(l1_ast, foo: l2_ast)

# Which should give us:
->(a, b) {
  div {
    # we make up new arg names, declare them as local vars, assign the callsite
    # args to them, then compose the inlined AST with the rewritten arg names.
    __1_x = a
    __1_y = b
    __1_z = 42
    # inlined call - the local var is also renamed
    __1_yy = __1_y + 2
    bar(__1_x, __1_yy, __1_z + 3)
  }
}
```

## Nested inlining

If we want to be able to inline recursively - we need to start from the
innermost level:

```ruby
layout = ->(**, &) {
  html { body(**, &) }
}

content = ->(title:, cards:, **) {
  h2 title
  cards.each { |c|
    card(**c)
  }
}

Papercraft.extension[:card] = ->(heading:, text:) {
  div(class: 'card') {
    h3 heading
    p text
  }
}

Papercraft.html(layout, info, &content)
# Which should give us:

->(**__kwargs__) {
  html {
    body {
      # args assignment
      __1_title = __kwargs__[:title]
      __1_cards = __kwargs__[:cards]
      h2 __1_title
      __1_cards.each { |c|
        # args assignment
        __2_heading = c[:heading]
        __2_text = c[:text]
        div(class: 'card') {
          h3 __2_heading
          p __2_text
        }
      }
    }
  }
}
```

So actually, we should do the inlining from the outside in, since that we can
track the renaming prefixes more easily:

```ruby
CN = Ruby::Prism::CallNode
BAN = Ruby::Prism::BlockArgumentNode

def inline(ast, inline_ctx = {}, &)
  mutate(ast) { |n|
    if n in (CN(receiver: nil) | BAN(expression: nil)) && (n2 = yield(n))
      # recursive inlining:
      n2 = inline(ast, inline_ctx, &)
      # return the rewritten inlined ast to the mutator
      next rewrite_inlined_ast(n2, ctx, &)
    end
    n
  }
end
```

## Synthesizing nodes

I already wrote about coming up with a special DSL for expressing keyword
syntax, e.g. `__.rescue` etc. In order to synthesize those nodes, we can employ
`quote` for creating nodes, then mutating them as we need:

```ruby
# call spec: __.rescue(MyError, :e)
def __.rescue(klass, ref)
  rescue_node = quote { begin; rescue; end }.rescue_node
  # naive impl?
  rescue_node.copy(exception: klass, reference: ref)
end
```

To create a local var read node:

```ruby
def __.local_get(name)
  quote { v = 1; v }.body[1].copy(name:)
end

def __.local_set(name, value)
  quote { v = 1 }.body[0].copy(name:, value:)
end
```

## Unquote that returns multiple statements

A common use for unquote (from the examples above) is e.g.:

```ruby
quote { unquote foo.map { quote { unquote(it) + 42 } } }
```

In that case, unquote returns an array of AST nodes. To integrate this into the
surrounding quote is not a problem. We just need to wrap the array in a `begin`
block:

```ruby
def wrap_statements(statements)
  ast = quote { begin; 1; end }
  mutate(ast, ast.statements: statements)
end
```

We can even simplify this to not use quote (since quote involves a bit of overhead):

```ruby
def gen_ast(str)
  Ruby::Prism.parse(str).value.statements.body[0]
end

def wrap_statements(statements)
  ast = gen_ast('begin; 1; end')
  mutate(ast, ast.statements: statements)
end
```

# 2026-11-11

## Improving sourcemaps when inlining synthetic ASTs

When we compose synthetic ASTs, we want to conserve the original location.
Example:

```ruby
def __.local_get(name)
  gen_ast('begin; v = 1; v; end').body[1].copy(name:)
end

# somewhere inside the bowels of *quote*:
mutate(ast) { |n|
  case n
  in __.match("local[]" => name) # pattern detection is a whole other subject
    next __.gen.local_get(name).copy(location: n.location)
  end
}
```

We can also make the synthetic node API take the form of e.g.:

```ruby
module Synthetizer
  module_function

  # The first param is always the original node, which permits us to copy the
  # original node's location
  def local_get(orig)
    replace(orig, gen_ast('begin; v = 1; v; end').body[1], name: n.name)
  end
end

# This allows us to do:
mutate(ast) { |n|
  case n
  in __.match("local[]" => name) # pattern detection is a whole other subject
    next Synthesizer.local_get(n, name)
  end
}
```

## Pattern matching nodes

We may want to have a shorthand for `Ruby::Prism`, and maybe also for common
node types:

```ruby
P = Ruby::Prism
CN = P::CallNode
AN = P::ArgumentsNode
```

We can then match like this:

```ruby
def match_local_get(n)
  n in CN(
    name: :[],
    arguments: AN(
      arguments: [v]
    ),
    receiver: CN(
      name: :local,
      receiver: CN(
        name: :__,
        receiver: nil
      )
    )
  )
end
```

We might imagine a shorter, more convenient way to do this with a DSL?

```ruby
# our pattern is something like:
__.local[xxx]

# So we maybe we can do:
n in Matcher.new.call(:__, ).call(:local).call(:[]).arguments(v)
```

The problem is that we need to match from the outside inwards, and the above
syntax matchees calls from the inside out (because in the AST the inside-most
call node is `__`).

A different way would be maybe:

```ruby
# Following the tree structure, but with shorter syntax
n in M.call(:[], arguments: [v], receiver: M.call(:local, receiver: M.call(:__, receiver: nil)))
```

Somewhat shorter, but still reads quite horribly. Going back to the inside-out
syntax from above:

```ruby
n in Matcher.new.call(:__, receiver: nil).call(:local).call(:[], arguments: v)
```

Better, but what about?

```ruby
Matcher.pattern { __.local[__?] }.match(ast)

# or
n in
```

A PoC implementation can be found in `test/match.rb`

# 2026-11-12

## Finding nodes

Another way we can dig and match against an AST is by providing a navigation
path. Think CSS selectors, but for AST:

```ruby
Steadfast.find(ast) { CallNode(name: :foo, receiver: nil) } #=> returns found node, or nil
Steadfast.find_all(ast) { SymbolNode }
```

So, this kind of DSL is somewhat similar to the Prism DSL for synthesizing, and the
pattern matching DSL, except that this uses `instance_eval { ... }`. So,
revisiting the pattern matching syntax:

```ruby
CN = Ruby::Prism::CallNode
AN = Ruby::Prism::ArgumentsNode

# matching __.local[__?]
n in CN(name: :[], arguments: AN(arguments: [v]), receiver: CN(name: :local, receiver: CN(name: :__, receiver: nil)))
```

## Conclusion

- For internal use, we might have to make do with pattern matching, because it
  lets us capture properties into variables that we can then use for processing.
- We can eventually implement `Steadfast.find` and `Steadfast.find_all`.
- We can provide a `Steadfast.walk` that, like `Steadfast.mutate` walks the tree.

- More generally, in terms of general API design, I like the idea of having a
  single entrypoint to the steadfast functionality in the form of a set of
  methods on the `Steadfast` module:

  ```ruby
  # already implemented
  Steadfast.ast(obj, **)
  Steadfast.source(obj, **)
  Steadfast.translate_backtrace(bt)

  #
  Steadfast.quote(*) { * }
  Steadfast.mutate(ast, *) { * }
  Steadfast.walk(ast) { * }
  Steadfast.find(ast) { * }
  Steadfast.find_all(ast) { * }

  ```

## More uses of eval in the wild

Those projects are vibe-coded, but still the idea in itself is interesting:

- https://github.com/julik/protostar - pure-Ruby protobufs compiler - takes a
  `.proto` spec file and compiles it into a decoder/encoder. Interestingly, the
  compiled code is not a low-level builder of classes and decoder/encoder, but
  instead emits a DSL, which raises the question, why?

- https://github.com/yosiat/panko_serializer - a pure-ruby JSON serializer -
  compiles serializers for fixed-shape objects, so it seems. This is also
  vibe-coded, so it seems,

# 2026-11-13

## Macros

Some possible uses:

- DSL
- Loop unrolling
- Method decoration

How would the API look?

```ruby
macro(:add_getter) { |k, v|
  __.def(unquote(k)) { unquote(v) }
}

add_getter(:foo, 42)
```

Another way to do this would be:

```ruby
def add_getter(k, v)
  ast = Steadfast.quote { __.def(unquote(k)) { unquote(v) } }
  Steadfast.eval_ast(ast, self)
end
```

# 2026-11-18

## Tool for determining if an AST is "static"

When compiling a template, Papercraft needs to know if an attribute, or an
"innerText" of a tag is static, meaning the value can be determined at compile
time. If yes, we can safely emit a string containing the escaped value, instead of emitting a call to `ERB.escape_html` with the dynamic value.

Hence, it would *behoove* us to have a utility for that:

```ruby
Steadfast.static?(ast)
```

We can check if an AST is totally static by checking for the absence of:

- method calls
- local var read / write
- instance var read / write
- class var read / write
- logic: if, case, while, rescue, etc.

```ruby
# @param ast [Prism::Node]
# @return [bool]
def static?(ast)
  !find(ast) do
    case it
    when P::CallNode, P::LocalVariableWriteNode, P::LocalVariableReadNode, ...
      true
    end
    false
  end
end
```

Easy!

## More on inlining

One major hurdle we might have with inlining is that we can't always inline
things. We can inline only values that are known at the moment of inlining. Take
the following exmaple:

```ruby
layout = ->(**, &) {
  html {
    body {
      render(**, &)
    }
  }
}

template = Papercraft.apply(layout, :foo) { |foo:, **| h1 foo }
Papercraft.html(template) #=> HTML
```

The call to `#apply` should already perform the inline! In this case, there's no
problem to do the inlining, since apply gets the inner template as a block and
can inline it. But let's look at a different case:

```ruby
layout = ->(**, &) {
  html {
    body {
      render &, **
    }
  }
}

# ad-hoc usage of the layout
Papercraft.html(layout) { h1 'foo' } #=> HTML

# if we want a reusable template, we'll do like the above, using apply:
template = Papercraft.apply(layout, :foo) { |foo:, **| h1 foo }
```

So, first of all there's the realisation that we need to do the inling when
doing the apply, otherwise there's no point, since it's a one-off thing.

We can also provide a template as a normal argument:

```ruby
layout = ->(header:, content:, **) {
  html {
    body {
      header { render header, ** }
      content { render content, ** }
    }
  }
}

template = Papercraft.apply(layout, header: ->(**) { h1 'Header' })

Papercraft.html(template, content: ->(**) { p 'Content' })
```

So, when we call `Papercraft.apply` we only know what `header` is, but `content`
is still not bound to a value that we know of. So, here's how this can be done:

```ruby
# we put aside for the moment the application of values other than sub-templates
def apply(template, **kwargs, &block)
  Steadfast.inline(template) { |n| # visited node
    # when we call inline, we need to provide a block that visits each node, and
    # if that node needs to be replaced with an inlined AST, it returns the AST
    # of the inlined node, so for example, we inline calls to `render` as
    # follows:
    case n
    when P::CallNode(receiver: nil, name: :render)
      arg0 = n.arguments.arguments[0]
      if arg0 in P::CallNode(receiver: nil)
        if (v = kwargs[arg0.name]) && v.is_a?(Proc)
          next Steadfast.to_ast(v) #=> we return the AST to be inlined
          end
      end
    end
    nil
  }
end
```

So basically, inline is an enhanced version of mutate that knows how to inline
ASTs into each other (more specifically, ASTs of Procs) and perform
argument/parameter substitution.

## Inlining things other than Procs

We can inline methods, but is there any meaning for inlining of other stuff?
Well, we can inline values as substitutions for local variables, but we can do
this with `mutate`, so no, `inline` is only for inlining procs or methods, so in
principle the block given to `inline` can return a proc or a method:

```ruby
def apply(template, **kwargs, &block)
  Steadfast.inline(template) { |n| # visited node
    case n
    when P::CallNode(receiver: nil, name: :render)
      arg0 = n.arguments.arguments[0]
      if arg0 in P::CallNode(receiver: nil)
        v = kwargs[arg0.name]
        next v if v.is_a?(Proc)
      end
    end
    nil
  }
end
```

## Alternative syntax to `render` for rendering sub-templates

I don't like the current `render_children` syntax. Some alternatives:

```ruby
# using yield for rendering the given block
layout = ->(**) {
  html {
    body {
      yield **
    }
  }
}

# using render
layout = ->(foo:, bar:, **) {
  html {
    body {
      render(foo, **)
      render(bar, **)
    }
  }
}
```

## More inlining

So, we established that with Papercraft, we inline at the moment of apply. But
there are also other things that we can inline, if they are available in the
binding, or if they are defined as extensions, that we can inline when compiling
the template:

```ruby
header ->(title) {
  h2(title)
}

card = ->(title:, text:) {
  tag.card {
    render header, title
    p(text)
  }
}

template = ->() {
  div {
    render card, title: 'Foo', text: 'foofoo'
    render card, title: 'Bar', text: 'barbar'
  }
}

# inlined it will be:
->() {
  div {
    tag.card {
      h2('Foo')
      p('foofoo')
    }
    tag.card {
      h2('Bar')
      p('barbar')
    }
  }
}
```

So inlining needs to be recursive:

```ruby
def inline_template(template, **kwargs)
  ast = Steadfast.to_ast(template)
  ast2 = Steadfast.inline(ast) do |n|
    if n in P::CallNode(receiver: nil, name: :render)
      v = inline_render_call(n, kwargs, template.binding)
      next v if v
    end
    nil
  end
  Steadfast.eval_ast(ast2, template.binding)
end

# @param node [Prism::Node]
# @param kwargs [Hash] template kwargs
# @param binding [Binding] template binding
# @return [Proc, nil]
def inline_render_call(node, kwargs, binding)
  arg0 = node.arguments.arguments[0]
  if arg0 in P::CallNode(receiver: nil)
    v = find_inlined_value(arg[0].name, kwargs, binding)
    return inline_template(v) if v.is_a?(Proc)
  end
  nil
end

# Finds a inline value in the given kwargs or binding
#
# @param name [Symbol] call name
# @param kwargs [Hash] template kwargs
# @param binding []
def find_inline_value(name, kwargs, binding)
  v = kwargs[name]
  return v if v

  if binding.local_variable_defined?(name)
    return binding.local_variable_get(name)
  end

  nil
end
```

## Derivative ASTs and source maps

When doing an `eval_ast` or converting synthesized / modified ASTs to code and
then to actual proc or method, we keep a source map, which we can then use to
translate error backtrace entries to the original source locations.

But what happens when we create a 2nd-order derivation? If we further derive an
AST from the derived proc/method, we'll get (with the current
`translate_backtrace` implementation) incorrect source locations. Keeping track
of the original locations will be impossible, because any part of the derived
proc's code might come from any arbitrary location.

So what we need to do is:

A. Make the backtrace translation recursive, so if a backtrace entry translates
to a synthetic source location, we need to further search for it. This should be
quite simple.

B. Automatically give each piece of synthesized code a unique fake source
filename, so it can be used for referencing source locations. Right now, this is
done by calling `to_source` with the `source_location:` option, but should be
done automatically.

## Interesting article: The Magic of Partial Evaluation

Touches on some of the things I'm doing:

https://jimmyhmiller.com/magic-of-partial-evaluation

# 2026-11-20

## Pipelines

Can we do pipelines with AST transformation?

```ruby
'zip, br,zstd'.pipe {
  _.split(',').map(&:strip) >>
  select_compression(prefer: 'br') >>
  setup_compression()
}

# which might be expanded into:
_ = `zip, br,zstd`
_ = _.split(',').map(&:strip)
_ = select_compression(_, prefer: 'br')
setup_compression(_)

# Or, if we want to convert to a single expression without local variable
# assignment:
setup_compression(select_compression(`zip, br,zstd`.split(',').map(&:strip), prefer: 'br'))
```

This is where we can use a macro:

```ruby
module Pipeline
  include Steadfast::Macro

  macro def pipe(ast)
    mutate(ast) do |n, &|
      next nil if !(n in P::CallNode(name: :>>, receiver: P::CallNode))

      call_node = n.arguments.arguments[0]
      arguments = Steadfast::Compose.arguments(mutate(n.receiver, &), call_node.arguments)
      call_node.copy(arguments:)
    }
  end
end

class ServerConnection
  include Pipeline

  def auto_compress!(accept_encoding, preferred)
    pipe {
      accept_encoding.split(',').strip(&:) >>
      select_compression_algorithm(preferred:) >>
      setup_compression()
    }
  end

  # This is automatically "expanded" to:
  def auto_compress!(accept_encoding, preferred)
    setup_compression(
      select_compression_algorithm(
        accept_encoding.split(',').strip(&:),
        preferred:
      )
    )
  end
end
```

## An assert macro

```ruby
module Testing
  include Steadfast::Macro

  macro def assert(ast)
    quote {
      if Testing.test_mode?
        raise "Assertion failed" if !(unquote(ast))
      end
    }
  end
end

class MyTest
  include Testing

  def test_this
    assert 1 == 1 #=> nil
    assert 1 == 2 #=> BOOM!
  end
end
```

# 2026-11-23

## Partial evaluation and specialization

https://phoenix.labri.fr/software/tempo/
https://jimmyhmiller.com/magic-of-partial-evaluation

For example, when doing `Papercraft.apply`, we can "specialize" the template by
analyzing and identifying all parts of it that are static (e.g. value is known
at compile time). Those parts can be computed at runtime, and replaced by the
computation result.

So, maybe we can have a `Steadfast.specialize` method, such that:

```ruby
template = ->(foo) {
  if foo
    div foo
  else
    div "bar"
  end
}
```

So, if we had a `Steadfast.specialize` tool, we could do:

```ruby
specialized_template = Steadfast.specialize(template, foo: true)

# Which would give us
specialized_template = ->() {
  div "foo"
}
```

This means we need to somehow be able to tell if a statement is all static
(given the specialization parameters, in this case the value of `foo`), or are
there any method calls (apart from HTML tag method calls). So we might be able
to do this with a `walk` tool:

```ruby
Steadfast.specialize(template, foo: true) { |n, values|
  # the block just needs to return true if the visited node is static
}

# @param l [Proc]
# @param values [Hash]
# @block [Proc, nil]
# @return [P::Node]
def Steadfast.specialize(l, values, &block)
  Steadfast.rewrite(ast) { |n, &b|
    # we return n (no rewrite) if dynamic
    case n
    in  P::CallNode
      next n if !block || !block.(n)

    in  P::LocalVariableWriteNode,
        P::InstanceVariableReadNode, P::InstanceVariableWriteNode

    in P::LocalVariableReadNode
      next n if !(l.binding.local_variable_defined?(n.name) || values.key?(n.name))

      # rewrite with actual value
      Steadfast.unquote(
        values.key?(n.name) ? values[n.name] : l.binding.local_variable_get(n.name)
      )
    in P::StatementsNode
      n2 = Steadfast.rewrite(ast, &b)
      next n if n2 == n

      # compile time evaluation
      value = eval(Steadfast.to_source(n2), l.binding)
      Steadfast.unquote(value)
    else
      n
    end
  }
end
```

# 2026-11-24

## Synthesizing AST Nodes

Writing the rewrite tests has been a learning experience. Especially evolving
from using `eval` to invoking `Prism.parse`:

```ruby
def make_loop(body_node, statements)
  loc = source_location(body_node)
  loop_node = Ruby::Prism.parse(
    'loop do; 1; end', filepath: loc[0], line: loc[1]
  ).value.statements.body[0]
  loop_node.send(:source).__filename__ = loc[0]

  loop_block_body = loop_node.block.body
  Steadfast.rewrite(loop_node, loop_block_body => { body: statements })
end
```

What we can extract from here is that when synthesizing a node, we can take an
original node which provides the source location, and feed that into the call to
`Prism.parse`. We can also provide additional options to improve parsing, e.g.
frozen_string_literal:

https://docs.ruby-lang.org/en/master/Ruby/Prism.html#method-c-parse

```ruby
# @param obj [P::Node, P::Location]
# @return [Array] [filename, lineno]
def get_source_location(obj)
  filename = obj.send(:source).__filename__ || raise('No filename set')
  lineno = obj.start_line
  [filename, lineno]
end

# @param src [String]
# @param loc [P::Node, P::Location]
# @param lvars [Array<Symbol>] optional local var list
# @param binding [Binding] optional binding
# @return [P::Node]
def make_node(src, loc: nil, lvars: nil, binding: nil)
  loc = orig_node && get_source_location(orig_node)
  scopes = [(binding&.local_variables || []), lvars].compact
  opts = {
    raise_error:            true,
    freeze:                 true,
    frozen_string_literal:  true,
    filepath:               loc && loc[0],
    line:                   loc && loc[1],
    scopes:                 scopes
  }
  Prism.parse(src, **opts).value.statements.body[0]
end
```

## Testing make_node

1. 100% synthetic AST, building the following:

  ```ruby
  ->(x) {
    loop {
      if x
        break 42
      else
        raise 'foo'
      end
    }
  }
  ```

2. Test lvars, binding

3. Test source location - in conjunction with Steadfast.rewrite

  ```ruby
  # take this
  ->(x) {
    case x
    when 1
      foo
    when 2
      bar
    end
  }
  ```

  - Replace foo with synthetic `rescue 'foo'`, bar with `rescue 'bar'`
  - Use `eval_ast` to do source mapping
  - Check backtrace translation

