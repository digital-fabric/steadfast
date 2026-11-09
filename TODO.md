## Sourcifier

- [v] Make all tests pass, import all missing Sourcifier code
- [ ] Redesign source maps
  - [ ] Extend `Ruby::Prism::Source` to have a `__filename__` attribute
  - [ ] In `Steadfast#to_ast`, we need to get a hold of the AST's source, and
    set its `__filename__` attribute:

    ```ruby
    # Node#source is a private method
    ast.send(:source).__filename__ ||= obj.source_location.first
    ```

  - [ ] When emitting stuff into the buffer, keep track of the line number
  - [ ] When emitting a `location` (`emit_code`):
    - [ ] keep track of the last location
    - [ ] compare the current location against the last, if the line number changed, or `send(:source).__filename__` changed,
      - [ ] store the location info (filename, lineno) in a hash
  - [ ] In order to generate a sourcemap, the sourcifier should know the
        `source_location` (real or synthetic) of the given AST, which is
        normally that of the AST root. We'll add a `sourcemap:` option to
        `Steadfast.to_source`, which tracks source location mapping.
  - [ ] In addition, we might want to add a `Steadfast.eval(ast, receiver, binding)` method that does the whole stick:

    ```ruby
    def self.eval_ast(ast, receiver, binding, translate_backtrace: false)
      src = to_source(ast, source_map: translate_backtrace)
      loc = source_location(ast)
      receiver.instance_eval(src, binding, loc[:filename], loc[:line])
    end
    ```

  - [ ] Implement a `Steadfast#translate_backtrace(location)`
