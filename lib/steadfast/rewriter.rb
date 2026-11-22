# frozen_string_literal: true

module Steadfast
  class Rewriter
    def self.rewrite(ast, **replacements, &block)
      block ||= ->(n) do
        if (v = replacements[n]) && v.is_a?(Hash)
          n.copy(**v)
        else
          replacements.key?(n) ? replacements[n] : n
        end
      end
      ast.accept(new(block))
    end

    def initialize(rewrite_block)
      @rewrite_block = rewrite_block
    end

    def method_missing(sym, n) = sym !~ /^visit_/ ? super(sym, n) : visit(n)

    def visit(n)
      n2 = @rewrite_block.(n, &@rewrite_block)
      return n2 if n2 != n

      changes = {}
      n.deconstruct_keys(nil).each do |k, v|
        if v.is_a?(Ruby::Prism::Node)
          res = visit(v)
          changes[k] = res if (res != v)
        elsif v.is_a?(Array) && v[0].is_a?(Ruby::Prism::Node)
          v2 = v.map { visit(it) }
          changes[k] = v2 if v2 != v
        end
      end
      changes.empty? ? n : n.copy(**changes)
    end
  end
end
