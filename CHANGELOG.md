# 0.5.0 2026-11-26

- Add examples
- Sourcifier: fix source formatting for `ForwardingSuperNode`, `ImaginaryNode`, `ProgramNode`
- Add support for AlternationPatternNode
- Add `Steadfast.quote` - Include `Steadfast::Quote` methods in `Steadfast`
- `Steadfast.rewrite` - raise on invalid AST

# 0.4.0 2026-11-25

- Improve sourcifier output
- Implement `quote` and `unquote`
- Implement additional `make_xxx` methods
- Implement `make_statements`
- Implement `make_literal`
- Implement `make_node`

# 0.3.0 2026-11-24

- Implement `Steadfast.find_all`
- Implement `Steadfast.find`
- Implement `Steadfast.walk`
- Add `Visitor` base class, base `Rewriter` off it

# 0.2.0 2026-11-24

- Use frozen string literals in `eval_ast`
- Refactor source mapping into separate module

# 0.1.0 2026-11-23

- Improve source mapping, make it work for derivative synthetic ASTs
- Add automatic source location info in `Steadfast.eval_ast`

# 0.0.3 2026-11-23

- Implement `Steadfast.eval_ast`
- Implement `Steadfast.rewrite`
- Improve sourcemap calculation when doing inlining

# 0.0.2 2026-11-09

- Emit newline upon detecting a source change while sourcifying an AST
- Implement source mapping
- Implement `Steadfast.translate_backtrace`

# 0.0.1 2026-11-06

- Implement `Steadfast.to_source`
