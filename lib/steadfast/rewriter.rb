# frozen_string_literal: true

module Steadfast

  # The Rewriter class is used for rewriting ASTs.
  class Rewriter
    # Rewrites the given AST with a either a hash of node replacements, or a
    # block which is invoked for each node in the AST.
    #
    # @param ast [Ruby::Prism::Node] AST
    # @replacements [Hash] replacements
    # @return [Ruby::Prism::Node]
    def self.rewrite(ast, **replacements, &rewrite_block)
      rewrite_block ||= ->(n) do
        if (v = replacements[n]) && v.is_a?(Hash)
          n.copy(**v)
        else
          replacements.key?(n) ? replacements[n] : n
        end
      end
      ast.accept(new(rewrite_block))
    end

    # Initializes the rewriter.
    #
    # @param rewrite_block [Proc]
    # @return [void]
    def initialize(rewrite_block)
      @rewrite_block = rewrite_block
    end

    # Intercepts visit_xxxx method calls.
    #
    # @param sym [Symbol]
    # @return [void]
    def method_missing(sym, *, **, &)
      sym =~ /^visit_/ ? visit(*) : super(sym, *, **, &)
    end

    # Visits the given node, and subsequently its subnodes, invoking the rewrite
    # block, and returning either the original node or its replacement.
    #
    # @param n [Ruby::Prism::Node]
    # @return [Ruby::Prism::Node]
    def visit(n)
      n2 = @rewrite_block.(n, &@rewrite_block)
      return n2 if n2 != n

      changes = {}
      n.deconstruct_keys(nil).each do |k, v|
        if v.is_a?(Ruby::Prism::Node)
          v2 = visit(v)
          changes[k] = v2 if v2 != v
        elsif v in [Ruby::Prism::Node, *]
          v2 = v.map { visit(it) }
          changes[k] = v2 if v2 != v
        end
      end
      changes.empty? ? n : n.copy(**changes)
    end
  end
end
