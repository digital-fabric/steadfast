# frozen_string_literal: true

module Steadfast

  # The Visitor class is used for traversing an AST, visiting each node in it.
  class Visitor
    # Initializes the visitor with the given visitor block.
    #
    # @param block [Proc]
    # @return [void]
    def initialize(&block)
      @block = block
    end

    # Intercepts visit_xxxx method calls.
    #
    # @param sym [Symbol]
    # @return [void]
    def method_missing(sym, *, **, &)
      sym =~ /^visit_/ ? visit(*) : super(sym, *, **, &)
    end

    # Visits the given node, and subsequently its subnodes, invoking the block.
    #
    # @param n [Ruby::Prism::Node]
    # @return [void]
    def visit(n)
      @block.(n, &@block)

      n.deconstruct_keys(nil).each do |k, v|
        if v.is_a?(Ruby::Prism::Node)
          visit(v)
        elsif v in [Ruby::Prism::Node, *]
          v.each { visit(it) }
        end
      end
    end
  end
end
