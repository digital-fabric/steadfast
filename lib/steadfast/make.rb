# frozen_string_literal: true

module Steadfast
  module Make
    # @param src [String]
    # @param location [Ruby::Prism::Node, Ruby::Prism::Location]
    # @param lvars [Array<Symbol>] optional local var list
    # @param binding [Binding] optional binding
    # @return [Ruby::Prism::Node]
    def make_node(src, location: nil, lvars: nil, binding: nil)
      loc = location && __get_source_location__(location)
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

    IDENTIFIER_RE = /^[^\(\)\;\:\s]+$/

    def make_def(name, params: nil, body:, location: nil)
      raise SyntaxError, 'Invalid method name' if !(IDENTIFIER_RE === name)
      
      n = make_node("def #{name}(x); 1; end", location:)
      n.copy(body:, parameters: params)
    end

    def make_lvar_read(name, location: nil)
      raise SyntaxError, 'Invalid identifier name' if !(IDENTIFIER_RE === name)
      
      make_node(name.to_s, lvars: [name.to_sym], location:)
    end

    def make_array(array, location: nil)
      raise ArgumentError, "Not an array" if !array.is_a?(Array)

      n = make_node('[]', location:)
      Steadfast.rewrite(n, n => { elements: array.map { make_literal(it, location:) } })
    end

    def make_hash(hash, location: nil)
      raise ArgumentError, "Not a hash" if !hash.is_a?(Hash)

      n = make_node('{ x => 1 }', location:)
      assoc_node = n.elements[0]
      elements = hash.map { |k, v|
        Steadfast.rewrite(
          assoc_node,
          assoc_node => {
            key: make_literal(k, location:),
            value: make_literal(v, location:)
          }
        )
      }
      Steadfast.rewrite(n, n => { elements: })
    end

    def make_literal(v, location: nil)
      case v
      when Integer, Float, String, Symbol, Range, Regexp, nil, true, false
        make_node(v.inspect, location:)
      when Array
        make_array(v, location:)
      when Hash
        make_hash(v, location:)
      else
        raise ArgumentError, "Can't make AST node for #{v.inspect}"
      end
    end
    
    private

    # @param location [Ruby::Prism::Node, Ruby::Prism::Location]
    # @return [Array] [filename, lineno]
    def __get_source_location__(location)
      filename = location.send(:source).__filename__ || raise('No filename set')
      lineno = location.start_line
      [filename, lineno]
    end

    def __sanitize__(v, pat, msg = nil)
      if !(pat === v)
        raise Steadfast::Error, msg || "Given value doesn't match #{pat.inspect}"
      end
      v
    end
  end
end
