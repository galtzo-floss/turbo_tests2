require_relative "lib/turbo_tests2/version"

Gem::Specification.new do |spec|
  spec.name = "turbo_tests2"
  spec.version = TurboTests::VERSION
  spec.platform = Gem::Platform::RUBY

  spec.summary = "`turbo_tests2` is a drop-in replacement for `serpapi/turbo_tests` and `grosser/parallel_tests` with incremental summarized output. Source code of `turbo_test2` gem is based on Discourse and Rubygems work in this area (see README file of the source repository)."
  spec.homepage = "https://github.com/galtzo-floss/turbo_tests2"
  spec.license = "MIT"

  spec.authors = ["Peter H. Boling", "Illia Zub"]
  spec.email = ["floss@galtzo.com"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/galtzo-floss/turbo_tests2"
  spec.metadata["changelog_uri"] = "https://github.com/galtzo-floss/turbo_tests2/releases"

  spec.required_ruby_version = ">= 2.7"

  spec.add_dependency("parallel_tests", ">= 3.3.0", "< 6")
  spec.add_dependency("rspec", ">= 3.10")

  spec.add_development_dependency("appraisal", "~> 2.5")
  spec.add_development_dependency("pry", "~> 0.14")
  spec.add_development_dependency("rake", "~> 13.0")

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    %x(git ls-files -z).split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.executables = ["turbo_tests2"]
end
