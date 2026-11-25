## MiniTest

### lib/minitest/spec.rb

https://github.com/minitest/minitest/blob/bd26321cdb4acf35aa8cf5a27c0bb6707972754c/lib/minitest/spec.rb#L7

```ruby
def infect_an_assertion meth, new_name, dont_flip = false # :nodoc:
  block = dont_flip == :block
  dont_flip = false if block

  self.class_eval <<-EOM, __FILE__, __LINE__ + 1
    def #{new_name}(*args, **kws)
      raise "Calling ##{new_name} outside of test." unless ctx
      case
      when #{!!dont_flip} then
        ctx.#{meth}(target, *args, **kws)
      when #{block} && Proc === target then
        ctx.#{meth}(*args, **kws, &target)
      else
        ctx.#{meth}(args.first, target, *args[1..-1], **kws)
      end
    end
  EOM
end
```

```ruby
def infect_an_assertion meth, new_name, dont_flip = false # :nodoc:
  block = dont_flip == :block
  dont_flip = false if block

  self.class_eval quote  {
    __.def(unquote(new_name), *args, **kws) do
      raise unquote("Calling #{unquote(new_name)} outside of test.") unless ctx
      case
      when unquote(!!dont_flip) then
        __.call(ctx, unquote(meth), target, *args, **kws)
      when unquote(block) && Proc === target then
        __.call(ctx, unquote(meth), *args, **kws, &target)
      else
        __.call(ctx, unquote(meth), args.first, target, *args[1..-1], **kws)
      end
    end
  }
end
```

## Faraday

### lib/faraday/connection.rb

https://github.com/lostisland/faraday/blob/670f3a6aef13734841e926f991cbb1c47bc3c5ee/lib/faraday/connection.rb#L198

```ruby
METHODS_WITH_QUERY.each do |method|
  class_eval <<-RUBY, __FILE__, __LINE__ + 1
    def #{method}(url = nil, params = nil, headers = nil)
      run_request(:#{method}, url, nil, headers) do |request|
        request.params.update(params) if params
        yield request if block_given?
      end
    end
  RUBY
end
```

```ruby
METHODS_WITH_QUERY.each do |method|
  class_eval quote {
    __.def(unquote(method), url = nil, params = nil, headers = nil) do
      run_request(unquote(method.to_sym), url, nil, headers) do |request|
        request.params.update(params) if params
        yield request if block_given?
      end
    end
  }
end
```

### lib/faraday/options.rb

https://github.com/lostisland/faraday/blob/670f3a6aef13734841e926f991cbb1c47bc3c5ee/lib/faraday/options.rb#L176

```ruby
def self.memoized(key, &block)
  unless block
    raise ArgumentError, '#memoized must be called with a block'
  end

  memoized_attributes[key.to_sym] = block
  class_eval <<-RUBY, __FILE__, __LINE__ + 1
    remove_method(key) if method_defined?(key, false)
    def #{key}() self[:#{key}]; end
  RUBY
end
```

```ruby
def self.memoized(key, &block)
  unless block
    raise ArgumentError, '#memoized must be called with a block'
  end

  memoized_attributes[key.to_sym] = block
  class_eval quote {
    remove_method(key) if method_defined?(key, false)
    __.def(unquote(key)) { self[unquote(key.to_sym)] }
  }
end
```

### lib/faraday.rb

https://github.com/lostisland/faraday/blob/670f3a6aef13734841e926f991cbb1c47bc3c5ee/lib/faraday.rb#L150

```ruby
METHODS_WITH_QUERY.each do |method|
  class_eval <<-RUBY, __FILE__, __LINE__ + 1
    # def get(url = nil, params = nil, headers = nil, &block)
    #   default_connection.get(url, params, headers, &block)
    # end
    def #{method}(url = nil, params = nil, headers = nil, &block)
      default_connection.#{method}(url, params, headers, &block)
    end
  RUBY
end
```

```ruby
METHODS_WITH_QUERY.each do |method|
  class_eval quote {
    __.def(unquote(method), url = nil, params = nil, headers = nil, &block) do
      __.call(default_connection, unquote(method), url, params, headers, &block)
    end
  RUBY
end
```

Alternative syntax for doing a __.call:

```ruby
METHODS_WITH_QUERY.each do |method|
  class_eval quote {
    __.def(unquote(method), url = nil, params = nil, headers = nil, &block) do
      default_connection.__.call(unquote(method), url, params, headers, &block)
    end
  RUBY
end
```

## pundit

### spec/support/lib/controller.rb

https://github.com/varvet/pundit/blob/ea9e31a2d7993f038ee52b94ccc9c7411637ba89/spec/support/lib/controller.rb#L21

```ruby
def helper_method(method)
  View.class_eval quote {
    __.def(unquote(method), *args, **kwargs, &block)
      controller.__.call(unquote(method.to_sym), *args, **kwargs, &block)
    end
  }
end
```

## kaminari

### lib/kaminari/helpers/paginator.rb

https://github.com/kaminari/kaminari/blob/d957f0c5f3d5e972ac19eb0830f1985fd454035e/kaminari-core/lib/kaminari/helpers/paginator.rb#L69

```ruby
%w[first_page prev_page next_page last_page gap].each do |tag|
  eval <<-DEF, nil, __FILE__, __LINE__ + 1
    def #{tag}_tag
      @last = #{tag.classify}.new(@template, param_name: @param_name,
        theme: @theme, views_prefix: @views_prefix, internal_params: @params,
        internal_url_cache: @url_cache, internal_partial_cache: @partial_cache,
        **@options
      )
    end
  DEF
end
```

```ruby
%w[first_page prev_page next_page last_page gap].each do |tag|
  eval quote {
    __.def(unquote("#{tag}_tag")) do
      @last = unquote(tag.classify).new(
        @template, param_name: @param_name, theme: @theme, views_prefix: @views_prefix,
        internal_params: @params, internal_url_cache: @url_cache,
        internal_partial_cache: @partial_cache, **@options
      )
    end
  }
end
```

### lib/kaminari/models/array_extension.rb

https://github.com/kaminari/kaminari/blob/d957f0c5f3d5e972ac19eb0830f1985fd454035e/kaminari-core/lib/kaminari/models/array_extension.rb#L42

```ruby
class_eval <<-RUBY, __FILE__, __LINE__ + 1
  def #{Kaminari.config.page_method_name}(num = 1)
    num = num.respond_to?(:to_i) ? num.to_i : 1
    offset(limit_value * ((num = num.to_i - 1) < 0 ? 0 : num))
  end
RUBY
```

### lib/kaminari/activerecord/active_record_model_extension.rb

https://github.com/kaminari/kaminari/blob/d957f0c5f3d5e972ac19eb0830f1985fd454035e/kaminari-activerecord/lib/kaminari/activerecord/active_record_model_extension.rb#L26

```ruby
eval <<-RUBY, nil, __FILE__, __LINE__ + 1
  def self.#{Kaminari.config.page_method_name}(num = nil)
    num = num.respond_to?(:to_i) ? num.to_i : 1
    per_page = max_per_page && (default_per_page > max_per_page) ? max_per_page : default_per_page
    # spawn only once rather than calling limit, offset, and extending, each of which copies the Relation
    all.spawn.limit!(per_page).offset!(per_page * ((num = num.to_i - 1) < 0 ? 0 : num)).extending!(Kaminari::ActiveRecordPageScope)
  end
RUBY
```

```ruby
eval quote {
  __.def(self.unquote(Kaminari.config.page_method_name), num = nil) do
    num = num.respond_to?(:to_i) ? num.to_i : 1
    per_page = max_per_page && (default_per_page > max_per_page) ? max_per_page : default_per_page
    # spawn only once rather than calling limit, offset, and extending, each of which copies the Relation
    all.spawn.limit!(per_page).offset!(per_page * ((num = num.to_i - 1) < 0 ? 0 : num)).extending!(Kaminari::ActiveRecordPageScope)
  end
}
```

## actiontext

### lib/action_text/attribute.rb

https://github.com/rails/rails/blob/d5c10191684c845d4ddb53587d3a2965270369fc/actiontext/lib/action_text/attribute.rb#L54

```ruby
def has_rich_text(name, encrypted: false, strict_loading: strict_loading_by_default, store_if_blank: true)
  class_eval <<-CODE, __FILE__, __LINE__ + 1
    def #{name}
      rich_text_#{name} || build_rich_text_#{name}
    end

    def #{name}?
      rich_text_#{name}.present?
    end
  CODE

  if store_if_blank
    class_eval <<-CODE, __FILE__, __LINE__ + 1
      def #{name}=(body)
        self.#{name}.body = body
      end
    CODE
  else
    class_eval <<-CODE, __FILE__, __LINE__ + 1
      def #{name}=(body)
        if body.present?
          self.#{name}.body = body
        else
          if #{name}?
            self.#{name}.body = body
            self.#{name}.mark_for_destruction
          end
        end
      end
    CODE
  end

  rich_text_class_name = encrypted ? "ActionText::EncryptedRichText" : "ActionText::RichText"
  has_one :"rich_text_#{name}", -> { where(name: name) },
    class_name: rich_text_class_name, as: :record, inverse_of: :record, autosave: true, dependent: :destroy,
    strict_loading: strict_loading

  scope :"with_rich_text_#{name}", -> { includes("rich_text_#{name}") }
  scope :"with_rich_text_#{name}_and_embeds", -> { includes("rich_text_#{name}": { embeds_attachments: :blob }) }
end
```

```ruby
def has_rich_text(name, encrypted: false, strict_loading: strict_loading_by_default, store_if_blank: true)
  class_eval quote {
    __.def(unquote(name)) do
      __.call(unquote("rich_text_#{name}")) || __.call(unquote("build_rich_text_#{name}"))
    end

    __.def(unquote("#{name}?"))
      __.call(unquote("rich_text_#{name}")).present?
    end
  }

  if store_if_blank
    class_eval quote {
      __.def(unquote("#{name}="), body) do
        self.__.call(unquote(name)).body = body
      end
    }
  else
    class_eval quote {
      __.def(unquote("#{name}="), body)
        if body.present?
          self.__.call(unquote(name)).body = body
        else
          if __.call(unquote("#{name}?"))
            self.__.call(unquote(name)).body = body
            self.__.call(unquote(name)).mark_for_destruction
          end
        end
      end
    }
  end

  rich_text_class_name = encrypted ? "ActionText::EncryptedRichText" : "ActionText::RichText"
  has_one :"rich_text_#{name}", -> { where(name: name) },
    class_name: rich_text_class_name, as: :record, inverse_of: :record, autosave: true, dependent: :destroy,
    strict_loading: strict_loading

  scope :"with_rich_text_#{name}", -> { includes("rich_text_#{name}") }
  scope :"with_rich_text_#{name}_and_embeds", -> { includes("rich_text_#{name}": { embeds_attachments: :blob }) }
end
```

## Roda

https://github.com/jeremyevans/roda/blob/cae641693f8f6f24a355e1d16f5df0c75bea9964/lib/roda.rb#L97-L193

```ruby
def define_roda_method(meth, expected_arity, &block)
  # RODA4: Make expected_arity optional, remove from callers
  if meth.is_a?(String)
    meth = roda_method_name(meth)
  end
  call_meth = meth


  # RODA4: Remove support for :check_arity, default to false behavior
  if (check_arity = opts.fetch(:check_arity, :warn)) && !block.lambda?
    required_args, optional_args, rest, keyword = _define_roda_method_arg_numbers(block)


    if keyword == :required && (expected_arity == 0 || expected_arity == 1)
      raise RodaError, "cannot use block with required keyword arguments when calling define_roda_method with expected arity #{expected_arity}"
    end


    case expected_arity
    when 0
      unless required_args == 0
        if check_arity == :warn
          RodaPlugins.warn "Arity mismatch in block passed to define_roda_method. Expected Arity 0, but arguments required for #{block.inspect}"
        end
        b = block
        block = lambda{instance_exec(&b)} # Fallback
      end
    when 1
      if required_args == 0 && optional_args == 0 && !rest
        if check_arity == :warn
          RodaPlugins.warn "Arity mismatch in block passed to define_roda_method. Expected Arity 1, but no arguments accepted for #{block.inspect}"
        end
        temp_method = roda_method_name("temp")
        class_eval("def #{temp_method}(_) #{meth =~ /\A\w+\z/ ? "#{meth}_arity" : "send(:\"#{meth}_arity\")"} end", __FILE__, __LINE__)
        alias_method meth, temp_method
        undef_method temp_method
        private meth
        alias_method meth, meth
        meth = :"#{meth}_arity"
      elsif required_args > 1
        if check_arity == :warn
          RodaPlugins.warn "Arity mismatch in block passed to define_roda_method. Expected Arity 1, but multiple arguments required for #{block.inspect}"
        end
        b = block
        block = lambda{|r| instance_exec(r, &b)} # Fallback
      end
    when :any
      if check_dynamic_arity = opts.fetch(:check_dynamic_arity, check_arity)
        if keyword
          # Complexity of handling keyword arguments using define_method is too high,
          # Fallback to instance_exec in this case.
          b = block
          block = if RUBY_VERSION >= '2.7'
            lambda{|*a, **kw| instance_exec(*a, **kw, &b)} # Keyword arguments fallback
          else
            # simplecov:disable
            lambda{|*a| instance_exec(*a, &b)} # Keyword arguments fallback
            # simplecov:enable
          end
        else
          arity_meth = meth
          meth = :"#{meth}_arity"
        end
      end
    else
      raise RodaError, "unexpected arity passed to define_roda_method: #{expected_arity.inspect}"
    end
  end


  define_method(meth, &block)
  private meth
  alias_method meth, meth


  if arity_meth
    required_args, optional_args, rest, keyword = _define_roda_method_arg_numbers(instance_method(meth))
    max_args = required_args + optional_args
    define_method(arity_meth) do |*a|
      arity = a.length
      if arity > required_args
        if arity > max_args && !rest
          if check_dynamic_arity == :warn
            RodaPlugins.warn "Dynamic arity mismatch in block passed to define_roda_method. At most #{max_args} arguments accepted, but #{arity} arguments given for #{block.inspect}"
          end
          a = a.slice(0, max_args)
        end
      elsif arity < required_args
        if check_dynamic_arity == :warn
          RodaPlugins.warn "Dynamic arity mismatch in block passed to define_roda_method. #{required_args} args required, but #{arity} arguments given for #{block.inspect}"
        end
        a.concat([nil] * (required_args - arity))
      end


      send(meth, *a)
    end
    private arity_meth
    alias_method arity_meth, arity_meth
  end


  call_meth
end
```

