# frozen_string_literal: true

require_relative "lib/auto/l18n/version"

Gem::Specification.new do |spec|
  spec.name = "auto-l18n"
  spec.version = Auto::L18n::VERSION
  spec.authors = ["Nicolas Reiner"]
  spec.email = ["nici.ferd@gmail.com"]

  spec.summary = "A gem to help with automatic localization for Rails applications."
  spec.description = "This gem provides a set of tools to streamline the process of adding and managing translations in Rails applications."
  spec.homepage = "https://github.com/NicolasReiner/auto-l18n"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  # Publishing metadata
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/NicolasReiner/auto-l18n"
  spec.metadata["changelog_uri"] = "https://github.com/NicolasReiner/auto-l18n/blob/master/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/NicolasReiner/auto-l18n/issues"
  # Encourage MFA for publishing this gem (recommended by RubyGems)
  spec.metadata["rubygems_mfa_required"] = "false"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/]) ||
        %w[demo.rb examples.rb].include?(f)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  # Required runtime dependency for HTML parsing of view files
  spec.add_dependency "nokogiri", ">= 1.15", "< 2.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
