->(x) {
  Foo = 1
  Foo &&= 1
  Foo ||= 1
  Foo += 1

  Foo::Bar = 1
  Foo::Bar &&= 1
  Foo::Bar ||= 1
  Foo::Bar += 1

  Foo, Bar = [1, 2]
  Foo::Bar, Bar::Baz = [1, 2]

  # shareable_constant_value: literal
  Foo = { foo: 'bar' }
}
