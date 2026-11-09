# frozen_string_literal: true

module Steadfast

  # A Sourcifier is used for converting an AST to source code. Sourcifier is
  # implemented as an AST visitor that walks the AST, copying the relevant
  # strings from each node into a buffer, with the addition of whitespace,
  # commas, semicolons and newlines where applicable.
  class Sourcifier < Ruby::Prism::BasicVisitor
    # The following visit plans are used for generating code for node types that
    # don't require special logic. For each node, a list of fields/elements to
    # emit is given. For each node, a visit_xxx_node method is generated from
    # its visit plan. Nodes requiring special logic have normal visit_xxx_node
    # method below.
    VISIT_PLANS = {
      alias_global_variable:      [:keyword_loc, :whitespace, :new_name, :whitespace, :old_name],
      alias_method:               [:keyword_loc, :whitespace, :new_name, :whitespace, :old_name],
      and:                        [:left, :whitespace, :operator_loc, :whitespace, :right],
      assoc:                      [:key, :whitespace, :operator_loc, :whitespace, :value],
      assoc_splat:                [:operator_loc, :value],
      back_reference_read:        :emit_verbatim,
      block:                      [:opening_loc, :parameters, :newline, :body, :newline, :closing_loc],
      block_argument:             [:operator_loc, :expression],
      block_local_variable:       :emit_verbatim,
      block_parameter:            [:operator_loc, :name_loc],
      break:                      [:keyword_loc, :whitespace, :arguments],
      call_target:                [:receiver, :call_operator_loc, :message_loc],
      capture_pattern:            [:value, :whitespace, :operator_loc, :whitespace, :target],
      class:                      [:class_keyword_loc, :whitespace, :constant_path, :whitespace,
                                   :inheritance_operator_loc, :whitespace, :superclass, :newline,
                                   :body, :newline, :end_keyword_loc],
      class_variable_read:        :emit_verbatim,
      class_variable_target:      :emit_verbatim,
      class_variable_write:       [:name_loc, :operator_loc, :value],
      constant_path:              [:parent, :delimiter_loc, :name_loc],
      constant_path_write:        [:target, :operator_loc, :value],
      constant_read:              :emit_verbatim,
      constant_write:             [:name_loc, :operator_loc, :value],
      defined:                    [:keyword_loc, :lparen_loc, :value, :rparen_loc],
      else:                       [:else_keyword_loc, :newline, :statements],
      embedded_statements:        [:opening_loc, :statements, :closing_loc],
      embedded_variable:          [:operator_loc, :variable],
      ensure:                     [:ensure_keyword_loc, :newline, :statements],
      false:                      :emit_verbatim,
      flip_flop:                  [:left, :operator_loc, :right],
      float:                      :emit_verbatim,
      for:                        [:for_keyword_loc, :whitespace, :index, :whitespace, :in_keyword_loc,
                                   :whitespace, :collection, :whitespace, :do_keyword_loc, :newline,
                                   :statements, :newline, :end_keyword_loc],
      forwarding_arguments:       :emit_verbatim,
      forwarding_parameter:       :emit_verbatim,
      forwarding_super:           :emit_verbatim,
      global_variable_read:       :emit_verbatim,
      global_variable_target:     :emit_verbatim,
      global_variable_write:      [:name_loc, :operator_loc, :value],
      imaginary:                  :emit_verbatim,
      implicit:                   :nop,
      implicit_rest:              :nop,
      in:                         [:in_loc, :whitespace, :pattern, :whitespace, :then_loc],
      index_target:               [:receiver, :opening_loc, :arguments, :closing_loc],
      instance_variable_operator_write: [:name_loc, :whitespace, :binary_operator_loc, :whitespace, :value],
      instance_variable_or_write: [:name_loc, :whitespace, :operator_loc, :whitespace, :value],
      instance_variable_read:     :emit_verbatim,
      instance_variable_target:   :emit_verbatim,
      instance_variable_write:    [:name_loc, :operator_loc, :value],
      integer:                    :emit_verbatim,
      it_parameters:              :nop,
      it_local_variable_read:     :emit_verbatim,
      keyword_rest_parameter:     [:operator_loc, :name_loc],
      keyword_parameter:          :emit_verbatim,
      lambda:                     [:operator_loc, :parameters, :whitespace, :opening_loc, :newline, :body, :newline, :closing_loc],
      local_variable_and_write:   [:name_loc, :operator_loc, :value],
      local_variable_operator_write: [:name_loc, :binary_operator_loc, :value],
      local_variable_or_write:    [:name_loc, :operator_loc, :value],
      local_variable_read:        :emit_verbatim,
      local_variable_target:      :emit_verbatim,
      local_variable_write:       [:name_loc, :operator_loc, :value],
      match_predicate:            [:value, :whitespace, :operator_loc, :whitespace, :pattern],
      match_required:             [:value, :whitespace, :operator_loc, :whitespace, :pattern],
      match_write:                [:call],
      module:                     [:module_keyword_loc, :whitespace, :constant_path, :newline, :body, :newline, :end_keyword_loc],
      next:                       [:keyword_loc, :whitespace, :arguments],
      nil:                        :emit_verbatim,
      no_keywords_parameter:      :emit_verbatim,
      numbered_parameters:        :nop,
      optional_parameter:         [:name_loc, :whitespace, :operator_loc, :whitespace, :value],
      optional_keyword_parameter: [:name_loc, :whitespace, :value],
      or:                         [:left, :whitespace, :operator_loc, :whitespace, :right],
      parentheses:                [:opening_loc, :body, :closing_loc],
      pinned_expression:          [:operator_loc, :lparen_loc, :expression, :rparen_loc],
      pinned_variable:            [:operator_loc, :variable],
      rational:                   :emit_verbatim,
      redo:                       :emit_verbatim,
      regular_expression:         :emit_verbatim,
      required_parameter:         :emit_verbatim,
      required_keyword_parameter: :emit_verbatim,
      rescue_modifier:            [:expression, :whitespace, :keyword_loc, :whitespace, :rescue_expression],
      rest_parameter:             [:operator_loc, :name_loc],
      retry:                      :emit_verbatim,
      return:                     [:keyword_loc, :whitespace, :arguments],
      self:                       :emit_verbatim,
      singleton_class:            [:class_keyword_loc, :whitespace, :operator_loc, :whitespace, :expression,
                                   :newline, :body, :newline, :end_keyword_loc],
      source_encoding:            :emit_verbatim,
      source_file:                :emit_verbatim,
      source_line:                :emit_verbatim,
      splat:                      [:operator_loc, :expression],
      symbol:                     :emit_verbatim,
      true:                       :emit_verbatim,
      x_string:                   :emit_verbatim,
      yield:                      [:keyword_loc, :lparen_loc, :arguments, :rparen_loc]
    }

    attr_reader :buffer

    # Initializes the Sourcifier instance.
    #
    # @param start_line []
    # @return [void]
    def initialize(source_location: nil, sourcemap: false)
      @filename, @line = source_location
      @line ||= 1
      @sourcemap = sourcemap

      raise Steadfast::Error, "No filename given, can't generate source map" if @sourcemap && !@filename
    end

    # Converts the given AST to source code.
    #
    # @param ast [Ruby::Prism::Node] AST
    # @return [String] source code
    def to_source(ast)
      @buffer = +''
      visit(ast)
      @buffer
    end

    VISIT_PLANS.each do |kind, plan|
      define_method(:"visit_#{kind}_node") { |n| visit_node_with_plan(n, plan) }
    end

    def visit_array_node(node)
      emit_code(node.opening_loc)
      if node.opening_loc && node.opening_loc.slice =~ /^%/
        visit_space_separated_nodes(node.elements)
      else
        visit_comma_separated_nodes(node.elements)
      end
      emit_code(node.closing_loc)
    end

    def visit_array_pattern_node(node)
      emit_code(node.constant)
      emit_code(node.opening_loc)
      comma = visit_comma_separated_nodes(node.requireds, comma)
      if node.rest
        emit_comma if comma
        emit_code(node.rest)
        comma = true
      end
      visit_comma_separated_nodes(node.posts, comma)
      emit_code(node.closing_loc)
    end

    def visit_arguments_node(node, subscript = 0..-1)
      visit_comma_separated_nodes(node.arguments[subscript])
    end

    def visit_begin_node(node)
      emit_code(node.begin_keyword_loc)
      emit_newline
      emit_code(node.statements)
      emit_newline
      emit_code(node.rescue_clause)
      emit_newline
      emit_code(node.else_clause)
      emit_newline
      emit_code(node.ensure_clause)
      emit_newline
      emit_code(node.end_keyword_loc) if node.begin_keyword_loc
    end

    def visit_block_parameters_node(node)
      emit_code(node.opening_loc)
      emit_code(node.parameters)
      emit_semicolon if node.locals && node.locals.size > 0
      visit_comma_separated_nodes(node.locals)
      emit_code(node.closing_loc)
    end

    def visit_call_node(node)
      if (node.receiver && !node.call_operator_loc && !node.arguments && node.name != :[]) ||
         (node.receiver && !node.call_operator_loc && node.name == :!)
        return visit_call_node_unary_op(node)
      end

      return visit_call_node_attribute_write(node) if node.attribute_write?

      block = node.block

      emit_code(node.receiver)
      emit_code(node.call_operator_loc)
      if (ml = node.message_loc)
        ol = node.opening_loc
        emit_message_loc = !ol || (ol.start_line != ml.start_line) || (ol.start_column != ml.start_column)
        emit_whitespace if node.name =~ /^\+|\-|\*|\/|\&|\|\*\*|\&\&|\|\||\%$/
        emit_code(node.message_loc) if emit_message_loc
      end
      emit_code(node.opening_loc)
      emit_whitespace if !node.opening_loc && node.arguments
      emit_code(node.arguments)

      if block.is_a?(Ruby::Prism::BlockArgumentNode)
        emit_comma if node.arguments && node.arguments.arguments.size > 0
        emit_whitespace if !node.arguments
        emit_code(block)
        block = nil
      end
      emit_code(node.closing_loc)
      emit_semicolon if !node.opening_loc && node.arguments && node.arguments.arguments.size == 1 && node.arguments.arguments[0].is_a?(Ruby::Prism::SplatNode) && !block
      emit_whitespace if block
      emit_code(block)
    end

    def visit_call_node_attribute_write(node)
      emit_code(node.receiver)
      if node.call_operator_loc
        emit_code(node.call_operator_loc)
        emit_code(node.message_loc)
      end
      emit_code(node.opening_loc)
      comma = visit_arguments_node(node.arguments, 0..-2)
      if node.block
        emit_comma if comma
        emit_code(node.block)
      end
      emit_code(node.closing_loc)
      emit(" = ")
      emit_code(node.arguments.arguments[-1])
      return
    end

    def visit_call_node_unary_op(node)
      emit_code(node.message_loc)
      emit_code(node.opening_loc)
      emit_whitespace if !node.opening_loc
      emit_code(node.receiver)
      emit_code(node.closing_loc)
    end

    def visit_case_node(node)
      emit_code(node.case_keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
      node.conditions.each { |c| emit_newline; emit_code(c) }
      emit_newline if node.else_clause
      emit_code(node.else_clause)
      emit_newline
      emit_code(node.end_keyword_loc)
    end

    def visit_case_match_node(node)
      emit_code(node.case_keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
      emit_newline
      visit_comma_separated_nodes(node.conditions)
      emit_newline
      emit_code(node.end_keyword_loc)
    end

    def visit_def_node(node)
      emit_code(node.def_keyword_loc)
      emit_whitespace
      emit_code(node.receiver)
      emit_code(node.operator_loc)
      emit_code(node.name_loc)
      emit_whitespace if !node.lparen_loc
      emit_code(node.lparen_loc)
      emit_code(node.parameters)
      emit_code(node.rparen_loc)
      emit_code(node.equal_loc)
      emit_newline
      emit_code(node.body)
      emit_newline
      emit_code(node.end_keyword_loc)
    end

    def visit_find_pattern_node(node)
      emit_code(node.constant)
      emit_code(node.opening_loc)
      emit_code(node.left)
      comma = node.left
      comma = visit_comma_separated_nodes(node.requireds, comma)
      if node.right
        emit_comma if comma
        emit_code(node.right)
      end
      emit_code(node.closing_loc)
    end

    def visit_hash_node(node)
      emit_code(node.opening_loc)
      visit_comma_separated_nodes(node.elements)
      emit_code(node.closing_loc)
    end

    def visit_hash_pattern_node(node)
      emit_code(node.constant)
      emit_code(node.opening_loc)
      visit_comma_separated_nodes(node.elements)
      emit_code(node.closing_loc)
    end

    def visit_if_node(node)
      return visit_if_node_ternary(node) if !node.if_keyword_loc
      return visit_if_node_guard(node) if !node.end_keyword_loc

      emit_code(node.if_keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
      emit_newline
      emit_code(node.then_keyword_loc)
      emit_newline
      emit_code(node.statements)
      emit_newline
      emit_code(node.subsequent) if node.subsequent
      emit_newline
      emit_code(node.end_keyword_loc) if node.if_keyword_loc.slice == 'if'
    end

    def visit_if_node_guard(node)
      emit_code(node.statements)
      emit_whitespace
      emit_code(node.if_keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
    end

    def visit_if_node_ternary(node)
      emit_code(node.predicate)
      emit_whitespace
      emit_code(node.then_keyword_loc)
      emit_newline
      emit_code(node.statements)
      emit_newline
      emit_code(node.subsequent)
    end

    def visit_interpolated_symbol_node(node)
      heredoc = node.opening_loc && node.opening_loc.slice =~ /\<\</
      emit_code(node.opening_loc)
      emit_newline if heredoc
      last_part = nil
      node.parts.each { |p|
        if heredoc && last_part && p.location.start_line != last_part.location.start_line
          emit_newline
        end
        emit_code(p)
        last_part = p
      }
      emit_newline if heredoc
      emit_code(node.closing_loc)
    end
    alias_method :visit_interpolated_string_node, :visit_interpolated_symbol_node

    def visit_index_operator_write_node(node)
      emit_code(node.receiver)
      emit_code(node.opening_loc)
      emit_code(node.arguments)
      if node.block
        if !node.arguments.arguments.empty?
          emit_comma
        end
        emit_code(node.block)
      end
      emit_code(node.closing_loc)
      emit_whitespace
      emit_code(node.binary_operator_loc)
      emit_whitespace
      emit_code(node.value)
    end

    def visit_index_or_write_node(node)
      emit_code(node.receiver)
      emit_code(node.opening_loc)
      emit_code(node.arguments)
      if node.block
        if !node.arguments.arguments.empty?
          emit_comma
        end
        emit_code(node.block)
      end
      emit_code(node.closing_loc)
      emit_whitespace
      emit_code(node.operator_loc)
      emit_whitespace
      emit_code(node.value)
    end
    alias_method :visit_index_and_write_node, :visit_index_or_write_node

    def visit_interpolated_regular_expression_node(node)
      emit_code(node.opening_loc)
      node.parts.each { |p| emit_code(p) }
      emit_code(node.closing_loc)
    end

    def visit_interpolated_x_string_node(node)
      emit_code(node.opening_loc)
      node.parts.each { |p| emit_code(p) }
      emit_code(node.closing_loc)
    end

    def visit_keyword_hash_node(node)
      visit_comma_separated_nodes(node.elements)
    end

    def visit_multi_target_node(node)
      emit_code(node.lparen_loc)
      comma = visit_comma_separated_nodes(node.lefts)
      if node.rest
        emit_comma if comma
        emit_code(node.rest)
        comma = true
      end
      visit_comma_separated_nodes(node.rights, comma)
      emit_code(node.rparen_loc)
    end

    def visit_multi_write_node(node)
      emit_code(node.lparen_loc)
      comma = visit_comma_separated_nodes(node.lefts)
      if node.rest
        emit_comma if comma
        emit_code(node.rest)
        comma = true
      end
      visit_comma_separated_nodes(node.rights, comma)
      emit_code(node.rparen_loc)
      emit_whitespace
      emit_code(node.operator_loc)
      emit_whitespace
      emit_code(node.value)
    end

    def visit_parameters_node(node)
      comma = false
      comma = visit_comma_separated_nodes(node.requireds, comma)
      comma = visit_comma_separated_nodes(node.optionals, comma)
      if node.rest
        emit_comma if comma
        emit_code(node.rest)
        comma = true
      end

      comma = visit_comma_separated_nodes(node.posts, comma)
      comma = visit_comma_separated_nodes(node.keywords, comma)

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

    def visit_range_node(node)
      emit_code(node.left)
      emit_code(node.operator_loc)
      emit_whitespace if node.right.is_a?(Ruby::Prism::RangeNode)
      emit_code(node.right)
    end

    def visit_rescue_node(node)
      emit_code(node.keyword_loc)
      emit_whitespace
      visit_comma_separated_nodes(node.exceptions)
      emit_whitespace
      emit_code(node.operator_loc)
      emit_whitespace
      emit_code(node.reference)
      emit_newline
      emit_code(node.statements)
      emit_newline
      emit_code(node.subsequent)
    end

    def visit_statements_node(node)
      first = true
      node.body&.each do |n|
        emit_newline if !first
        visit(n)
        first = false
      end
    end

    def visit_string_node(node)
      heredoc = node.opening_loc && node.opening_loc.slice =~ /\<\</
      emit_code(node.opening_loc)
      emit_newline if heredoc
      emit_code(node.content_loc)
      emit_newline if heredoc
      emit_code(node.closing_loc)
    end

    def visit_super_node(node)
      emit_code(node.keyword_loc)
      emit_code(node.lparen_loc)
      emit_whitespace if !node.lparen_loc
      emit_code(node.arguments)
      emit_block_pre_rparen = node.block.is_a?(Ruby::Prism::BlockArgumentNode)
      if emit_block_pre_rparen
        emit_comma if node.arguments
        emit_code(node.block)
      end
      emit_code(node.rparen_loc)
      emit_code(node.block) if !emit_block_pre_rparen
    end

    def visit_undef_node(node)
      emit_code(node.keyword_loc)
      emit_whitespace
      visit_comma_separated_nodes(node.names)
    end

    def visit_unless_node(node)
      return visit_unless_node_guard(node) if !node.end_keyword_loc

      emit_code(node.keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
      emit_code(node.then_keyword_loc)
      emit_newline
      emit_code(node.statements)
      emit_newline
      emit_code(node.else_clause) if node.else_clause
      emit_newline
      emit_code(node.end_keyword_loc) if node.keyword_loc.slice == 'unless'
    end

    def visit_unless_node_guard(node)
      emit_code(node.statements)
      emit_whitespace
      emit_code(node.keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
    end

    def visit_until_node(node)
      return visit_until_node_guard(node) if !node.closing_loc

      emit_code(node.keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
      emit_newline
      emit_code(node.statements)
      emit_newline
      emit_code(node.closing_loc)
    end

    def visit_until_node_guard(node)
      emit_code(node.statements)
      emit_whitespace
      emit_code(node.keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
    end

    def visit_when_node(node)
      emit_code(node.keyword_loc)
      emit_whitespace
      visit_comma_separated_nodes(node.conditions)
      emit_newline
      emit_code(node.statements)
    end

    def visit_while_node(node)
      return visit_while_node_guard(node) if !node.closing_loc

      emit_code(node.keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
      emit_newline
      emit_code(node.statements)
      emit_newline
      emit_code(node.closing_loc)
    end

    def visit_while_node_guard(node)
      emit_code(node.statements)
      emit_whitespace
      emit_code(node.keyword_loc)
      emit_whitespace
      emit_code(node.predicate)
    end

    private

    # Visits a node with the given visit plan.
    #
    # @param node [Ruby::Prism::Node]
    # @param plan [Array<Symbol>, Symbol] visit plan
    # @return [void]
    def visit_node_with_plan(node, plan)
      return send(plan, node) if plan.is_a?(Symbol)

      plan.each do |sym|
        case sym
        when :newline
          emit_newline
        when :whitespace
          emit_whitespace
        else
          obj = node.send(sym)
          emit_code(obj)
        end
      end
    end

    # Visit an array of nodes, with commas emitted between them. The given comma
    # flag determines whether to emit a comma before visiting the next node in
    # the list, and is set to true after visiting a node.
    #
    # @param list [Array<Ruby::Prism::Node>, nil] node list or nil
    # @param comma [bool] comma flag
    # @return [bool] comma flag
    def visit_comma_separated_nodes(list, comma = false)
      return false if !list

      list.each do |child|
        emit_comma if comma
        emit_code(child)
        comma = true
      end
      comma
    end

    # Visit an array of nodes separated by whitespace.
    #
    # @param list [Array<Ruby::Prism::Node>, nil] node list or nil
    # @return [void]
    def visit_space_separated_nodes(list)
      return if !list

      first = true
      list.each do |child|
        emit_whitespace if !first
        emit_code(child)
        first = false
      end
    end

    # Appends a node's location verbatim into the source code buffer.
    #
    # @param node [Ruby::Prism::Node]
    # @return [void]
    def emit_verbatim(node)
      emit_code(node.location)
    end

    # Appends a code location (or a node) into the source code buffer.
    #
    # @param loc [Ruby::Prism::Location, Ruby::Prism::Node, nil]
    # @return [void]
    def emit_code(loc)
      return if !loc
      return visit(loc) if loc.is_a?(Ruby::Prism::Node)

      record_loc_source_mapping(loc) if @sourcemap
      emit(loc.slice.chomp)
      @last_loc = loc
    end

    # Adds an entry to the sourcemap hash when detecting a change of line or
    # filename before emitting an AST location. If a change of filename is
    # detected, a newline is emitted in order to more accurately be able to
    # translate backtraces if needed.
    #
    # @param loc [Ruby::Prism::Location] code location
    # @return [void]
    def record_loc_source_mapping(loc)
      source = loc.send(:source)
      last_source = @last_loc&.send(:source)
      different_source = source != last_source
      changed = different_source || (@last_loc && (loc.start_line != @last_loc.start_line))
      return if !changed

      emit_newline if different_source && last_source
      Steadfast.sourcemap["#{@filename}:#{@line}"] ||= "#{loc.send(:source).__filename__}:#{loc.start_line}"
    end

    # Appends the given string into the source code buffer.
    #
    # @param str [String]
    # @return [void]
    def emit(str)
      @buffer << str
      @line += str.count("\n")
    end

    # Appends a newline into the source code buffer.
    #
    # @return [void]
    def emit_newline
      return if @buffer[-1] == "\n"
      
      @buffer << "\n"
      @line += 1
    end

    # Appends a space character into the source code buffer.
    #
    # @return [void]
    def emit_whitespace
      @buffer << " "
    end

    # Appends a comma into the source code buffer.
    #
    # @return [void]
    def emit_comma
      @buffer << ","
    end

    # Appends a semicolon into the source code buffer.
    #
    # @return [void]
    def emit_semicolon
      @buffer << ';'
    end

    # A nop method for doing nothing.
    #
    # @return [void]
    def nop(node); end
  end
end
