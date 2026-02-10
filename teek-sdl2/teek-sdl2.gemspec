require_relative "lib/teek/sdl2/version"

Gem::Specification.new do |spec|
  spec.name          = "teek-sdl2"
  spec.version       = Teek::SDL2::VERSION
  spec.authors       = ["James Cook"]
  spec.email         = ["jcook.rubyist@gmail.com"]

  spec.summary       = "GPU-accelerated SDL2 rendering for teek (Tk)"
  spec.description   = "Embeds an SDL2 renderer inside a Tk frame for GPU-accelerated drawing"
  spec.homepage      = "https://github.com/jamescook/teek"
  spec.licenses      = ["MIT"]

  spec.files         = Dir.glob("{lib,ext,test}/**/*").select { |f|
                         File.file?(f) && f !~ /\.(bundle|so|o|log)$/
                       } + %w[teek-sdl2.gemspec]
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/teek_sdl2/extconf.rb"]
  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "teek", ">= 0.1.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.0"
  spec.add_development_dependency "minitest", "~> 6.0"

  spec.requirements << "SDL2 development headers (libsdl2-dev or sdl2 via Homebrew)"
end
