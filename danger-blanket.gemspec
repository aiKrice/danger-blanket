# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "blanket/gem_version"

Gem::Specification.new do |spec|
  spec.name          = "danger-blanket"
  spec.version       = Blanket::VERSION
  spec.authors       = ["Christopher Saez"]
  spec.email         = ["saez.chris@gmail.com"]
  spec.description   = "A Danger plugin for reporting code coverage from any coverage tool, via pluggable parsers (xccov, Kover, or your own)."
  spec.summary       = spec.description
  spec.homepage      = "https://github.com/aiKrice/danger-blanket"
  spec.license       = "MIT"

  # git-tracked (for CI/reproducibility) but excluded from the packaged gem:
  # a real Xcode project used to smoke-test the Xccov parser locally,
  # heavier than something every `gem install danger-blanket` should have
  # to download.
  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
                          .reject { |f| f.start_with?("ios_smoke_test/") }
  spec.test_files    = spec.files.grep(%r{^spec/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7"

  spec.add_runtime_dependency "danger", "> 8.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.4"
end
