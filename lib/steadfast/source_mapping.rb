# frozen_string_literal: true

module Steadfast

  # SourceMapping manages the mapping of source locations for generated code, in
  # order to allow translating backtrace entries for raised exceptions such that
  # they will point to correct source locations in application code.
  module SourceMapping
    class << self
      # Adds a source mapping entry for the given path/line pairs.
      #
      # @param path1 [String]
      # @param line1 [Integer]
      # @param path2 [String]
      # @param line2 [Integer]
      # @return [void]
      def set(path1, line1, path2, line2)
        (@map ||= {})["#{path1}:#{line1}"] ||= "#{path2}:#{line2}"
      end
    
      # Translates entries in the given backtrace according to the global source
      # map.
      #
      # @param bt [Array<String>] backtrace
      # @return [Array<String>] translated source map
      def translate_backtrace(bt)
        return bt if !@map

        bt.map {
          if (m = it.match(/^(.+)(\:in.+)$/)) && (loc = find_sourcemap_entry(m[1]))
            "#{loc}#{m[2]}"
          else
            it
          end
        }
      end

      private
  
      # Returns a mapped location for the given location entry.
      #
      # @param loc [String] location string of the form file:line
      # @return [String, nil] mapped location
      def find_sourcemap_entry(loc)
        loc = @map[loc]
        return nil if !loc
  
        (loc =~ /^\(steadfast-[0-9a-f]+\)\:\d+$/) ? find_sourcemap_entry(loc) : loc
      end      
    end
  end
end
