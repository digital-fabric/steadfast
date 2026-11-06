# Preface

This document tracks the development work on the 2026 Ruby association grant.
Some preliminary design and research work has been done in other files in this
directory. Going forward, this document should record all work done as part of
the grant work.

# 2026-11-03

## The Debut

I'm not sure I want to do this as part of the Sirop gem. If I keep the same gem
as the "home" for this work, this means:

- A total rewrite for a version 2.0
- Getting rid of the whole `Sirop.to_ast(lambda/meth)` API.

Not a bad choice in and of itself, but is there a better name we can come up
with, and start from a clean slate? We can defer this decision for later, and
right now just use the Sirop repo as a starting point.

## Preliminary Work Plan

### November 2026

0. The baseline

- Ruby >=4.1 only (we need `#syntax_tree`)
- Use the built-in Prism, i.e. `Ruby::Prism`

1. Rewrite `Sirop.to_source(ast)` from scratch

Don't try to maintain the original whitespaces. Instead, put each statement on a
separate line.

2. Add support for sourcemaps

The generated source should be stored somewhere, each chunk of generated code
with a made-up filename. In IRB, it looks like `(irb):1`, so we might want to
have something like `(sirop-26c9bfb3):1`, which we can do with e.g.
`"sirop-#{SecureRandom.hex(4)}"`.

The mapping is generated automatically. The wrapping with a `rescue` that
translates backtraces is optional. The translation could be done manually using
e.g. `Sirop.translate_backtrace(bt)`, or by telling Sirop to add backtrace
translation to the code, e.g. `Sirop.to_source(ast, wrap: true)`, which will
inject the following into the method/lambda definition:

```ruby
def foo
  ...
rescue Exception => e
  raise Sirop.translate_exception_backtrace(e)
end
```

3. Test the hell out of it

- Source code generation: pass both original and generated code through a tool
  like rubyfmt or something in order to be able to compare them
- Source maps

4. Documentation

5. Blog posts

### December 2026

1. AST mutation

2. Basic quote/unquote functionality

3. Additional tools for generating code: `__.def`, `__.if` etc.

4. Lots of tests

5. Documentation

6. Blog posts

### January 2027

1. Compatibility with Different parts of Ruby API:

- For generated code: `Method#syntax_tree`, `Proc#syntax_tree`,
  `caller_locations[x].syntax_tree`
- Source maps
- The same but for code derived from code derived from code
- Interaction with `error_highlight` (https://github.com/ruby/error_highlight)
- Interaction with `

2. Examples + benchmarks

- Based on researched `eval` usages found "in the wild".
- Possible use cases as researched in the sketch document.

3. **Rewrite ERB compiler** using this.

3. Rewrite Papercraft compiler using this.

4. Rewrite Syntropy router compiler using this.

5. More tests, more docs

6. Blog posts

7. Interim report
