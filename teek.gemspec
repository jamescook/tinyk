require_relative "lib/teek/version"

Gem::Specification.new do |spec|
  spec.name          = "teek"
  spec.version       = Teek::VERSION
  spec.authors       = ["James Cook"]
  spec.email         = ["jcook.rubyist@gmail.com"]

  spec.summary       = %q{Small and simple Tk interface (8.6+ support)}
  spec.description   = %q{Tk interface}
  spec.homepage      = "https://github.com/jamescook/teek"
  spec.licenses      = ["MIT"]

  spec.files         = Dir.glob("{lib,ext,exe}/**/*").select { |f|
                         File.file?(f) && f !~ /\.(bundle|so|o|log)$/
                       } + %w[Rakefile LICENSE README.md teek.gemspec Gemfile]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/teek/extconf.rb"]
  spec.required_ruby_version = ">= 3.2"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "method_source", "~> 1.0"
  spec.add_development_dependency "prism", "~> 1.0"  # stdlib in Ruby 3.3+, gem for 3.2
  spec.add_development_dependency "base64"  # stdlib until Ruby 3.4, now bundled gem

  spec.metadata["msys2_mingw_dependencies"] = "teek"
end
