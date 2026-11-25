# Immediate

- Refactor test utility methods:
  - capture_exception
  - bt_entry_location
- Add support for :__nop__ return value of unquote block

# Next

- More quote scenarios in test/test_quote.rb
  - [ ] Memoize (sketches)
  - [ ] Loop unrolling (sketches)
  - [ ] Tail call optimization using quote (sketches)
  - [ ] Examples from the "unrolled code" article
  - [ ] Minitest's infect_an_assertion (see in in-the-wild)
  - [ ] Test DSL: `test 'foo' { assert(1  + 1 != 2) }` (see in sketches)
  - [ ] ERB template compiler (sketches)
  - [ ] Papercraft compiler (base capabilities) (sketches)
  - [ ] Syntropy router proc generation (sketches)

- More tools
  - [ ] partial_eval
  - [ ] inlinining
