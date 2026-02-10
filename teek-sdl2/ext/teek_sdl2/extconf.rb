# frozen_string_literal: true

require 'mkmf'

def find_sdl2
  # 1. Try SDL2_DIR env var first (explicit override)
  if ENV['SDL2_DIR']
    dir = ENV['SDL2_DIR']
    $INCFLAGS << " -I#{dir}/include"
    $LDFLAGS << " -L#{dir}/lib"
    if have_header('SDL2/SDL.h') && have_library('SDL2')
      return true
    end
    # Also try flat include layout (SDL.h directly in include/)
    if have_header('SDL.h') && have_library('SDL2')
      return true
    end
    abort "SDL2_DIR=#{dir} set but SDL2 not found there"
  end

  # 2. Try pkg-config
  if pkg_config('sdl2')
    return true
  end

  # 3. Try Homebrew paths (macOS)
  homebrew_dirs = [
    '/opt/homebrew/opt/sdl2',   # Apple Silicon
    '/usr/local/opt/sdl2'       # Intel
  ]

  homebrew_dirs.each do |dir|
    next unless File.directory?(dir)
    inc = "#{dir}/include"
    lib = "#{dir}/lib"

    # Homebrew SDL2 puts headers in include/SDL2/
    if File.exist?("#{inc}/SDL2/SDL.h")
      $INCFLAGS << " -I#{inc}"
      $LDFLAGS << " -L#{lib}"
      if have_header('SDL2/SDL.h') && have_library('SDL2')
        return true
      end
    end
  end

  # 4. Try standard system paths
  system_dirs = ['/usr/local', '/usr']
  system_dirs.each do |dir|
    inc = "#{dir}/include"
    lib = "#{dir}/lib"
    if File.exist?("#{inc}/SDL2/SDL.h")
      $INCFLAGS << " -I#{inc}"
      $LDFLAGS << " -L#{lib}"
      if have_header('SDL2/SDL.h') && have_library('SDL2')
        return true
      end
    end
  end

  # 5. MSYS2/MinGW (Windows)
  if RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
    # MSYS2 installs to the mingw prefix
    mingw_prefix = RbConfig::CONFIG['prefix']  # e.g. C:/msys64/mingw64
    inc = "#{mingw_prefix}/include"
    lib = "#{mingw_prefix}/lib"
    if File.exist?("#{inc}/SDL2/SDL.h")
      $INCFLAGS << " -I#{inc}"
      $LDFLAGS << " -L#{lib}"
      # MinGW uses -lSDL2 (same name)
      if have_header('SDL2/SDL.h') && have_library('SDL2')
        return true
      end
    end
  end

  false
end

unless find_sdl2
  abort <<~MSG
    SDL2 not found. Install it:
      macOS:   brew install sdl2
      Debian:  sudo apt-get install libsdl2-dev
      Windows: pacman -S mingw-w64-x86_64-SDL2  (MSYS2)
    Or set SDL2_DIR=/path/to/sdl2
  MSG
end

# SDL2_ttf for text rendering
unless pkg_config('SDL2_ttf') || have_library('SDL2_ttf', 'TTF_Init', 'SDL2/SDL_ttf.h')
  abort <<~MSG
    SDL2_ttf not found. Install it:
      macOS:   brew install sdl2_ttf
      Debian:  sudo apt-get install libsdl2-ttf-dev
      Windows: pacman -S mingw-w64-x86_64-SDL2_ttf  (MSYS2)
  MSG
end

$srcs = ['teek_sdl2.c', 'sdl2surface.c', 'sdl2bridge.c', 'sdl2text.c', 'sdl2pixels.c']

create_makefile('teek_sdl2')
