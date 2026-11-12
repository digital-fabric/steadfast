# frozen_string_literal: true

require_relative './helper'

P = Ruby::Prism

class Matcher
  def self.pattern(&block)
    ast = block.syntax_tree.block.body.body[0]
    convert_ast(ast)
  end

  def self.convert_ast(node)
    new(node.class, convert_node_props(node))
  end

  def self.convert_node_props(node)
    props = {}
    node.deconstruct_keys(nil).each { |k, v|
      next if k in :node_id | :location | /_loc$/
      next if node.is_a?(P::CallNode) && k in :message

      case v
      when Array
        v = v.map { it.is_a?(P::Node) ? convert_ast(it) : it }
      when P::Node
        v = convert_ast(v)
      end
      props[k] = v
    }
    props
  end

  attr_reader :type, :props
  
  def initialize(type = nil, props = nil)
    @type = type
    @props = props
  end

  def call(name, **props)
    if !@type
      @type = P::CallNode
      @props = { name:, receiver: nil, **props }
      self
    else
      Matcher.new(P::CallNode, { name:, receiver: self })
    end
  end

  def ===(v)
    match_obj(self, v)
  end
  alias_method :match, :===

  private

  def match_obj(o1, o2)
    case o1
    when Matcher
      return false if !o2.is_a?(o1.type)

      o2_props = o2.deconstruct_keys(nil)
      o1.props.each { |k, v|
        next if v in :__? | '__?'
        return false if !match_obj(v, o2_props[k])
      }
    when nil, Symbol, String, Integer, Float, true, false
      return false if o1 != o2
    when Array
      return false if !o2.is_a?(Array)

      o1.each_with_index { |v, i| return false if !match_obj(v, o2[i]) }
    end
    true
  end
end

n = P.parse('__.local[v]').value.statements.body[0]
LocalVarRead = Matcher.pattern { __.local[__?] }

m = n in LocalVarRead
# m = n in M(foo: :bar)#M.match(n)
# m = n in Matcher.pattern { __.local[__?] }

p m ? :ok : :no_match
