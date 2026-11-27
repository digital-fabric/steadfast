# frozen_string_literal: true

require 'securerandom'

require 'steadfast/ast'
require 'steadfast/source_mapping'
require 'steadfast/sourcifier'
require 'steadfast/visitor'
require 'steadfast/rewriter'
require 'steadfast/make'
require 'steadfast/quote'

# Tell Ruby to keep script lines in memory, so calling Proc#syntax_tree or
# Method#syntax_tree will work.
RubyVM.keep_script_lines = true

# Steadfast is a metaprogramming gem for Ruby. Steadfast provides a
# general-purpose mecehanism for generating and rewriting Ruby code at runtime.
module Steadfast
  # Extensions to Ruby::Prism::Source
  module PrismSourceExtensions
    # The __filename__ attribute lets us track the source location for a given
    # AST.
    attr_accessor :__filename__
  end
  ::Ruby::Prism::Source.include(PrismSourceExtensions)

  # A base error class for Steadfast errors
  class Error < StandardError
  end

  class << self
    include Steadfast::AST
    include Steadfast::Make
    include Steadfast::Quote
  end
end
