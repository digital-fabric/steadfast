# frozen_string_literal

require 'bundler/inline'

gemfile do
  source 'https://gem.coop'
  gem 'steadfast', path: '..'
end

include Steadfast::Quote

def create_validator(*conds)
  ast = quote(binding) {
    ->(v) {
      unquote conds.map { |c|
        quote {
          raise ArgumentError unless unquote(c) === v
        }
      }
      v
    }
  }
  Steadfast.eval_ast(ast)
end


def capture_exception
  yield
  nil
rescue => e
  e
end

def bt_entry_location(entry)
  if (m = entry.match(/^([^\:]+)\:(\d+)/))
    [m[1], m[2].to_i]
  else
    nil
  end
end

StringValidator = create_validator(String, /abc/)

def validate_string(str)
  puts "Validating #{str.inspect}..."
  StringValidator.(str)
  puts "string is OK!"
  puts
rescue ArgumentError => e
  p e
  puts Steadfast::SourceMapping.translate_backtrace(e.backtrace)
  puts
end

loop do
  STDOUT << 'Enter a string: '
  str = STDIN.gets.chomp
  validate_string(str)
end
