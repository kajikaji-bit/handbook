# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "handbook"
  spec.version = "0.1.0"
  spec.summary = "Ruby applications responding to agent messages and tool results"
  spec.authors = ["Keisuke Kaji"]
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir.glob("lib/**/*.rb", base: __dir__)
  spec.require_paths = ["lib"]
  spec.add_dependency "rack", "~> 3.2"
end
