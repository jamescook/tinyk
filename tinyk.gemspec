Gem::Specification.new do |spec|
  spec.name          = "tinyk"
  spec.version       = "0.1.0"
  spec.authors       = ["James Cook"]
  spec.email         = ["jcook.rubyist@gmail.com"]

  spec.summary       = %q{Small and simple Tk interface (8.6+ support)}
  spec.description   = %q{Tk interface}
  spec.homepage      = "https://github.com/jamescook/tinyk"
  spec.licenses      = ["MIT"]

  spec.files         = Dir.glob("{lib,ext,exe,sample}/**/*").select { |f| File.file?(f) } +
                       %w[Rakefile LICENSE README.md tinyk.gemspec Gemfile]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/tinyk/extconf.rb"]
  spec.required_ruby_version = ">= 3.2"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "method_source", "~> 1.0"
  spec.add_development_dependency "prism", "~> 1.0"  # stdlib in Ruby 3.3+, gem for 3.2
  spec.add_development_dependency "base64"  # stdlib until Ruby 3.4, now bundled gem

  spec.metadata["msys2_mingw_dependencies"] = "tinyk"
end
