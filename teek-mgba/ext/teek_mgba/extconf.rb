# frozen_string_literal: true

require 'mkmf'

def add_mgba_deps
  # Common dependencies of libmgba (needed when linking statically)
  $libs << " -lz" unless $libs.include?('-lz')
  $libs << " -lm" unless $libs.include?('-lm')
  $libs << " -lpthread" unless $libs.include?('-lpthread')

  # libmgba's static build also links libpng and libzip
  pkg_config('libpng') || ($libs << " -lpng" unless $libs.include?('-lpng'))
  pkg_config('libzip') || ($libs << " -lzip" unless $libs.include?('-lzip'))

  # macOS: CoreFoundation for config directory resolution
  if RUBY_PLATFORM =~ /darwin/
    $LDFLAGS << " -framework CoreFoundation" unless $LDFLAGS.include?('CoreFoundation')
  end
end

def check_mgba
  add_mgba_deps
  have_header('mgba/core/core.h') && have_library('mgba')
end

def find_mgba
  # 1. MGBA_DIR env var (explicit override)
  if ENV['MGBA_DIR']
    dir = ENV['MGBA_DIR']
    $INCFLAGS << " -I#{dir}/include"
    $LDFLAGS << " -L#{dir}/lib"
    if check_mgba
      return true
    end
    abort "MGBA_DIR=#{dir} set but libmgba not found there"
  end

  # 2. Vendor install (from `rake mgba:deps`)
  vendor_install = File.expand_path('../../vendor/install', __dir__)
  if File.directory?(vendor_install)
    $INCFLAGS << " -I#{vendor_install}/include"
    $LDFLAGS << " -L#{vendor_install}/lib"
    if check_mgba
      return true
    end
  end

  # 3. pkg-config
  if pkg_config('mgba')
    add_mgba_deps
    return true
  end

  # 4. Homebrew / common prefix paths (macOS)
  brew_and_system = [
    '/opt/homebrew',      # Apple Silicon
    '/usr/local',         # Intel Homebrew / manual builds
    '/usr'                # System
  ]

  brew_and_system.each do |prefix|
    inc = "#{prefix}/include"
    lib = "#{prefix}/lib"
    if File.exist?("#{inc}/mgba/core/core.h")
      $INCFLAGS << " -I#{inc}"
      $LDFLAGS << " -L#{lib}"
      if check_mgba
        return true
      end
    end
  end

  false
end

unless find_mgba
  abort <<~MSG
    libmgba not found. Install it:

      macOS:   rake mgba:deps   (builds from source into vendor/)
      Debian:  sudo apt install libmgba-dev

    Or set MGBA_DIR=/path/to/mgba/install
  MSG
end

$srcs = ['teek_mgba.c']

create_makefile('teek_mgba')
