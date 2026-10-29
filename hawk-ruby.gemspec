# frozen_string_literal: true

require_relative "lib/hawk/version"

Gem::Specification.new do |spec|
  spec.name = "hawk-ruby"
  spec.version = Hawk::VERSION
  spec.authors = ["Leonid Svyatov"]
  spec.email = ["leonid@svyatov.com"]
  spec.summary = "Ruby error reporting for Hawk"
  spec.description = "A Ruby error catcher with optional framework integrations for Hawk."
  spec.homepage = "https://hawk.so"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb", "sig/hawk.rbs", "sig/hawk/**/*.rbs", "docs/*.md"] + %w[LICENSE README.md]
  spec.require_paths = ["lib"]
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "base64", ">= 0.2", "< 1"
  spec.add_dependency "json", ">= 2.7", "< 4"
end
