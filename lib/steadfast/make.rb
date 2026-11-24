# frozen_string_literal: true

module Steadfast
  module Make
    # @param src [String]
    # @param location [Ruby::Prism::Node, Ruby::Prism::Location]
    # @param lvars [Array<Symbol>] optional local var list
    # @param binding [Binding] optional binding
    # @return [Ruby::Prism::Node]
    def make_node(src, location: nil, lvars: nil, binding: nil)
      loc = location && get_source_location(location)
      scopes = [(binding&.local_variables || []), lvars].compact
      opts = {
        raise_error:            true,
        frozen_string_literal:  true,
        filepath:               loc && loc[0],
        line:                   loc && loc[1],
        scopes:                 scopes
      }
      ast = Ruby::Prism.parse(src, **opts).value.statements.body[0]
      ast.send(:source).__filename__ = loc[0] if loc
      ast
    end

    private

    # @param location [Ruby::Prism::Node, Ruby::Prism::Location]
    # @return [Array] [filename, lineno]
    def get_source_location(location)
      filename = location.send(:source).__filename__ || raise('No filename set')
      lineno = location.start_line
      [filename, lineno]
    end
  end
end
