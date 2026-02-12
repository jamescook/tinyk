require_relative "lib/teek/mgba/version"

Gem::Specification.new do |spec|
  spec.name          = "teek-mgba"
  spec.version       = Teek::MGBA::VERSION
  spec.authors       = ["James Cook"]
  spec.email         = ["jcook.rubyist@gmail.com"]

  spec.summary       = "GBA emulation for teek via libmgba"
  spec.description   = "Wraps libmgba's mCore C API for GBA emulation inside teek applications"
  spec.homepage      = "https://github.com/jamescook/teek"
  spec.licenses      = ["MIT"]

  spec.files         = Dir.glob("{lib,ext,test}/**/*").select { |f|
                         File.file?(f) && f !~ /\.(bundle|so|o|log)$/
                       } + %w[teek-mgba.gemspec]
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/teek_mgba/extconf.rb"]
  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "teek", ">= 0.1.2"
  spec.add_dependency "teek-sdl2", ">= 0.1.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.0"
  spec.add_development_dependency "minitest", "~> 6.0"

  spec.requirements << "libmgba development headers"
end
