module Steadfast
  class Sourcifier < Ruby::Prism::BasicVisitor
    VISIT_PLANS = {
      alias_global_variable:      [:keyword_loc, :new_name, :old_name],
      alias_method:               [:keyword_loc, :new_name, :old_name],
      and:                        [:left, :operator_loc, :right],
      assoc:                      [:key, :operator_loc, :value],
      assoc_splat:                [:operator_loc, :value],
      back_reference_read:        :emit_verbatim,
      block:                      [:opening_loc, :parameters, :body, :closing_loc],
      block_argument:             [:operator_loc, :expression],
      block_local_variable:       :emit_verbatim,
      block_parameter:            [:operator_loc, :name_loc],
      break:                      [:keyword_loc, :arguments],
      capture_pattern:            [:value, :operator_loc, :target],
      class_variable_read:        :emit_verbatim,
      class_variable_target:      :emit_verbatim,
      class_variable_write:       [:name_loc, :operator_loc, :value],
      constant_path:              [:parent, :delimiter_loc, :name_loc],
      constant_path_write:        [:target, :operator_loc, :value],
      constant_read:              :emit_verbatim,
      constant_write:             [:name_loc, :operator_loc, :value],
      defined:                    [:keyword_loc, :lparen_loc, :value, :rparen_loc],
      embedded_statements:        [:opening_loc, :statements, :closing_loc],
      embedded_variable:          [:operator_loc, :variable],
      false:                      :emit_verbatim,
      flip_flop:                  [:left, :operator_loc, :right],
      float:                      :emit_verbatim,
      forwarding_arguments:       :emit_verbatim,
      forwarding_parameter:       :emit_verbatim,
      forwarding_super:           :emit_verbatim,
      global_variable_read:       :emit_verbatim,
      global_variable_target:     :emit_verbatim,
      global_variable_write:      [:name_loc, :operator_loc, :value],
      imaginary:                  :emit_verbatim,
      implicit:                   :emit_nothing,
      implicit_rest:              :emit_nothing,
      in:                         [:in_loc, :pattern, :then_loc],
      index_target:               [:receiver, :opening_loc, :arguments, :closing_loc],
      instance_variable_read:     :emit_verbatim,
      instance_variable_target:   :emit_verbatim,
      instance_variable_write:    [:name_loc, :operator_loc, :value],
      integer:                    :emit_verbatim,
      it_parameters:              :emit_nothing,
      it_local_variable_read:     :emit_verbatim,
      keyword_rest_parameter:     [:operator_loc, :name_loc],
      keyword_parameter:          :emit_verbatim,
      local_variable_and_write:   [:name_loc, :operator_loc, :value],
      local_variable_operator_write: [:name_loc, :binary_operator_loc, :value],
      local_variable_or_write:    [:name_loc, :operator_loc, :value],
      local_variable_read:        :emit_verbatim,
      local_variable_target:      :emit_verbatim,
      local_variable_write:       [:name_loc, :operator_loc, :value],
      match_predicate:            [:value, :operator_loc, :pattern],
      match_required:             [:value, :operator_loc, :pattern],
      match_write:                [:call],
      next:                       [:keyword_loc, :arguments],
      nil:                        :emit_verbatim,
      no_keywords_parameter:      :emit_verbatim,
      numbered_parameters:        :emit_nothing,
      optional_parameter:         [:name_loc, :operator_loc, :value],
      optional_keyword_parameter: [:name_loc, :value],
      or:                         [:left, :operator_loc, :right],
      parentheses:                [:opening_loc, :body, :closing_loc],
      pinned_expression:          [:operator_loc, :lparen_loc, :expression, :rparen_loc],
      pinned_variable:            [:operator_loc, :variable],
      range:                      [:left, :operator_loc, :right],
      rational:                   :emit_verbatim,
      redo:                       :emit_verbatim,
      regular_expression:         :emit_verbatim,
      required_parameter:         :emit_verbatim,
      required_keyword_parameter: :emit_verbatim,
      rescue_modifier:            [:expression, :keyword_loc, :rescue_expression],
      rest_parameter:             [:operator_loc, :name_loc],
      retry:                      :emit_verbatim,
      return:                     [:keyword_loc, :arguments],
      self:                       :emit_verbatim,
      source_encoding:            :emit_verbatim,
      source_file:                :emit_verbatim,
      source_line:                :emit_verbatim,
      splat:                      [:operator_loc, :expression],
      string:                     [:opening_loc, :content_loc, :closing_loc],
      symbol:                     :emit_verbatim,
      true:                       :emit_verbatim,
      x_string:                   :emit_verbatim,
      yield:                      [:keyword_loc, :lparen_loc, :arguments, :rparen_loc]
    }

    attr_reader :buffer

    def initialize(**)
      @buffer = +''
    end

    def to_source(node)
      @buffer.clear
      visit(node)
      @buffer
    end

    VISIT_PLANS.each do |key, plan|
      sym = :"visit_#{key}_node"
      define_method(sym) { |n| visit_plan(plan, n) }
    end  

    def visit_lambda_node(node)
      emit_code(node.operator_loc)
      emit_code(node.parameters)
      emit_code(node.opening_loc)
      emit_code(node.body)#, semicolon: node.opening_loc.slice == 'do')
      # node.after_body_proc&.(node)
      emit_code(node.closing_loc)#, semicolon: node.closing_loc.slice == 'end')
    end

    def visit_block_parameters_node(node)
      emit_code(node.opening_loc)
      # emit_code(node.injected_parameters)
      emit_code(node.parameters)
      @semicolon = true if node.parameters
      visit_comma_separated_nodes(node.locals)
      emit_code(node.closing_loc)
      @semicolon = false
    end

    def visit_parameters_node(node)
      comma = false
      # injected_prefix is a custom attribute added by Sirop to the
      # ParametersNode class (in lib/sirop/prism_ext.rb). It is used
      # as a way to add a first parameter to a block or method.
      # if node.injected_prefix
      #   emit_code(node.injected_prefix)
      #   # adjust last_loc_end for proper whitespace after comma
      #   @last_loc_end[1] -= 2 if @last_loc_end
      #   # binding.irb
      #   comma = true
      # end

      comma = visit_comma_separated_nodes(node.requireds, comma)
      comma = visit_comma_separated_nodes(node.optionals, comma)
      if node.rest
        emit_comma if comma
        emit_code(node.rest)
        comma = true
      end
      comma = visit_comma_separated_nodes(node.posts, comma)
      comma = visit_comma_separated_nodes(node.keywords, comma)
      # if node.rest
      #   emit_comma if comma
      #   comma = true
      #   emit_code(node.rest)
      # end
      if node.keyword_rest
        emit_comma if comma
        comma = true
        emit_code(node.keyword_rest)
      end
      if node.block
        emit_comma if comma
        comma = true
        emit_code(node.block)
      end
    end

    def visit_statements_node(node)
      first = true
      node.body&.each do |n|
        emit_newline
        visit(n)
        first = false
      end
    end

    def visit_call_node(node)
      if node.receiver && !node.call_operator_loc && !node.arguments && node.name != :[]
        return visit_call_node_unary_op(node)
      end

      if node.receiver && !node.call_operator_loc && node.name == :!
        return visit_call_node_unary_op(node)
      end

      if node.attribute_write?
        return visit_call_node_attribute_write(node)
      end

      block = node.block

      emit_code(node.receiver)
      emit_code(node.call_operator_loc)
      if (ml = node.message_loc)
        ol = node.opening_loc
        emit_message_loc = !ol || (ol.start_line != ml.start_line) || (ol.start_column != ml.start_column)
        emit_code(node.message_loc) if emit_message_loc
      end
      emit_code(node.opening_loc)
      emit_code(node.arguments)

      if block.is_a?(Ruby::Prism::BlockArgumentNode)
        emit_comma if node.arguments && node.arguments.arguments.size > 0
        emit_code(block)
        block = nil
      end
      emit_code(node.closing_loc)
      emit_code(block)
    end

    def visit_arguments_node(node, subscript = 0..-1)
      visit_comma_separated_nodes(node.arguments[subscript])
    end

    private

    def visit_plan(plan, node)
      return send(plan, node) if plan.is_a?(Symbol)

      insert_semicolon = false
      plan.each_with_index do |sym, idx|
        if sym == :semicolon
          insert_semicolon = true
          next
        end

        obj = node.send(sym)
        emit_code(obj, semicolon: insert_semicolon)
        insert_semicolon = false
      end
    end

    def visit_comma_separated_nodes(list, comma = false)
      if list
        list.each do |child|
          emit_comma if comma
          emit_code(child)
          comma = true
        end
      end
      comma
    end

    def visit_space_separated_nodes(list)
      if list
        list.each do |child|
          emit_code(child)
        end
      end
    end

    def emit_verbatim(node)
      emit_code(node.location)
    end

    def emit_code(loc)
      return if !loc

#       if @last_loc
#         loc_loc = loc.is_a?(Ruby::Prism::Node) ? loc.location : loc
#         return if loc_loc.slice == @last_loc.slice && loc_loc.start_line == @last_loc.start_line &&
#           loc_loc.start_column == @last_loc.start_column
#       end
# 
#       semicolon ||= @semicolon
#       @semicolon = false
#       emit_semicolon(loc) if semicolon
      return visit(loc) if loc.is_a?(Ruby::Prism::Node)

      # adjust_whitespace(loc)
      # str = loc.slice
      # str = str.chomp if chomp
      str = loc.slice.chomp
      emit(str)
    end

    def emit(str)
      # update_source_map(str)
      @buffer << str
    end

    def emit_newline
      @buffer << "\n"
    end
  end
end
