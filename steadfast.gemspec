require_relative './lib/steadfast/version'

Gem::Specification.new do |s|
  s.name        = 'steadfast'
  s.version     = Steadfast::VERSION
  s.licenses    = ['MIT']
  s.summary     = 'Steadfast: modern metaprogramming for Ruby'
  s.author      = 'Sharon Rosner'
  s.email       = 'sharon@noteflakes.com'
  s.files       = `git ls-files README.md CHANGELOG.md lib`.split
  s.homepage    = 'http://github.com/digital-fabric/steadfast'
  s.metadata    = {
    "homepage_uri" => "https://github.com/digital-fabric/steadfast",
    "documentation_uri" => "https://www.rubydoc.info/gems/steadfast",
    "changelog_uri" => "https://github.com/digital-fabric/steadfast/blob/main/CHANGELOG.md"
  }

  s.rdoc_options = ["--title", "Steadfast", "--main", "README.md"]
  s.extra_rdoc_files = ["README.md"]
  s.require_paths = ["lib"]
  s.required_ruby_version = '>= 4.0'

  s.add_runtime_dependency      'debug_inspector'
  s.add_development_dependency  'minitest'
  s.add_development_dependency  'irb'
  s.add_development_dependency  'syntax_tree'
end
