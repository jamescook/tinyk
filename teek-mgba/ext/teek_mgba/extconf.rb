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
  have_header('mgba/core/core.h') or return false
  # Try with deps first (needed for static linking on macOS where
  # -undefined dynamic_lookup hides missing symbols until runtime)
  saved_libs = $libs.dup
  add_mgba_deps
  return true if have_library('mgba')
  # Fall back without deps (shared lib on Linux — deps baked into .so)
  $libs = saved_libs
  have_library('mgba')
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

  # 4. Homebrew / common prefix paths (macOS) / system paths (Linux)
  search_prefixes = [
    '/opt/homebrew',      # Apple Silicon
    '/usr/local',         # Intel Homebrew / manual builds
    '/usr'                # System
  ]

  # Debian/Ubuntu multiarch lib dirs (e.g. /usr/lib/aarch64-linux-gnu)
  multiarch_dirs = Dir.glob('/usr/lib/*-linux-gnu').select { |d| File.directory?(d) }

  search_prefixes.each do |prefix|
    inc = "#{prefix}/include"
    if File.exist?("#{inc}/mgba/core/core.h")
      $INCFLAGS << " -I#{inc}"
      multiarch_dirs.each { |d| $LDFLAGS << " -L#{d}" unless $LDFLAGS.include?(d) }
      $LDFLAGS << " -L#{prefix}/lib" unless $LDFLAGS.include?("#{prefix}/lib")
      if check_mgba
        return true
      end
    end
  end

  # 5. MSYS2/MinGW (Windows) — mgba has no .pc file so pkg-config won't find it
  if RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
    mingw_prefix = RbConfig::CONFIG['prefix']
    inc = "#{mingw_prefix}/include"
    lib = "#{mingw_prefix}/lib"
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
      Windows: pacman -S mingw-w64-ucrt-x86_64-mgba  (MSYS2)

    Or set MGBA_DIR=/path/to/mgba/install
  MSG
end

$srcs = ['teek_mgba.c']

create_makefile('teek_mgba')
