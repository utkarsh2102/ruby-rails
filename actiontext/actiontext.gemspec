# frozen_string_literal: true

version = File.read(File.expand_path("../RAILS_VERSION", __dir__)).strip

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = "actiontext"
  s.version     = version
  s.summary     = "Rich text framework."
  s.description = "Edit and display rich text in Rails applications."

  s.required_ruby_version = ">= 2.5.0"

  s.license  = "MIT"

  s.authors  = ["Javan Makhmali", "Sam Stephenson", "David Heinemeier Hansson"]
  s.email    = ["javan@javan.us", "sstephenson@gmail.com", "david@loudthinking.com"]
  s.homepage = "https://rubyonrails.org"

  s.files        = Dir["CHANGELOG.md", "MIT-LICENSE", "README.md", "lib/**/*", "app/**/*", "config/**/*", "db/**/*", "package.json"]
  s.require_path = "lib"

  s.metadata = {
    "source_code_uri" => "https://github.com/rails/rails/tree/v#{version}/actiontext",
    "changelog_uri"   => "https://github.com/rails/rails/blob/v#{version}/actiontext/CHANGELOG.md"
  }

  # NOTE: Please read our dependency guidelines before updating versions:
  # https://edgeguides.rubyonrails.org/security.html#dependency-management-and-cves

  s.add_dependency "activesupport", version
  s.add_dependency "activerecord",  version
  s.add_dependency "activestorage", version
  s.add_dependency "actionpack",    version

  s.add_dependency "nokogiri", ">= 1.8.5"
end
