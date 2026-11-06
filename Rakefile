# frozen_string_literal: true

task :default => :test
task :test do
  exec 'ruby test/run.rb'
end

task :release do
  require_relative './lib/steadfast/version'
  version = Steadfast::VERSION

  puts 'Building steadfast...'
  `gem build steadfast.gemspec`

  puts "Pushing steadfast #{version}..."
  `gem push steadfast-#{version}.gem`

  puts "Cleaning up..."
  `rm *.gem`
end
