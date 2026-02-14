# frozen_string_literal: true

require 'mkmf'

# On Windows (MinGW/UCRT), Ruby's win32.h and mingw-w64's sys/time.h both
# declare gettimeofday() with incompatible signatures.  Defining this guard
# suppresses mingw-w64's declaration so Ruby's is the only one in scope.
# See: https://github.com/rake-compiler/rake-compiler-dock/issues/32
if RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
  $CPPFLAGS << ' -D_GETTIMEOFDAY_DEFINED'
end

# Diagnostic dump for CI debugging — written before any search so we can
# always see what the environment looks like, even when the build fails.
def dump_mgba_search_diagnostics
  puts "=" * 60
  puts "teek-mgba extconf.rb diagnostics"
  puts "=" * 60
  puts "RUBY_PLATFORM:            #{RUBY_PLATFORM}"
  puts "RbConfig host_os:         #{RbConfig::CONFIG['host_os']}"
  puts "RbConfig prefix:          #{RbConfig::CONFIG['prefix']}"
  puts "RbConfig sitearchdir:     #{RbConfig::CONFIG['sitearchdir']}"
  puts "MGBA_DIR env:             #{ENV['MGBA_DIR'].inspect}"
  puts "PKG_CONFIG_PATH env:      #{ENV['PKG_CONFIG_PATH'].inspect}"
  puts "PATH (first 3):           #{ENV['PATH']&.split(File::PATH_SEPARATOR)&.first(3)&.join(', ')}"

  # Check common locations for mgba headers/libs
  candidates = [
    RbConfig::CONFIG['prefix'],
    "#{RbConfig::CONFIG['prefix']}/msys64/ucrt64",
    '/ucrt64',
    '/usr',
    '/usr/local',
    '/opt/homebrew',
  ]

  candidates.each do |prefix|
    inc = "#{prefix}/include/mgba/core/core.h"
    libs = Dir.glob("#{prefix}/lib/*mgba*") rescue []
    bins = Dir.glob("#{prefix}/bin/*mgba*") rescue []
    next if !File.exist?(inc) && libs.empty? && bins.empty?
    puts "\n  #{prefix}/"
    puts "    header: #{File.exist?(inc) ? 'FOUND' : 'missing'} (#{inc})"
    puts "    libs:   #{libs.empty? ? 'none' : libs.join(', ')}"
    puts "    bins:   #{bins.empty? ? 'none' : bins.join(', ')}"
  end

  # On Windows, also check what pacman says
  if RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
    msys2_root = "#{RbConfig::CONFIG['prefix']}/msys64"
    pacman = "#{msys2_root}/usr/bin/pacman"
    if File.exist?(pacman)
      puts "\npacman -Q mgba:"
      puts `"#{pacman}" -Q 2>&1`.lines.grep(/mgba/i).map { |l| "  #{l}" }.join
      puts "pacman -Ql mgba (headers/libs only):"
      ql = `"#{pacman}" -Ql mingw-w64-ucrt-x86_64-mgba 2>&1`
      puts ql.lines.grep(/\.(h|a|dll|lib|pc)/).first(20).map { |l| "  #{l}" }.join
    else
      puts "\npacman not found at #{pacman}"
    end
  end

  puts "=" * 60
end

dump_mgba_search_diagnostics

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
    ruby_prefix = RbConfig::CONFIG['prefix']
    msys2_prefixes = [
      "#{ruby_prefix}/msys64/ucrt64",  # UCRT64 env inside Ruby's MSYS2
      "#{ruby_prefix}/msys64/mingw64", # MINGW64 env
      ruby_prefix,                      # Direct prefix (standalone MSYS2)
    ]

    msys2_prefixes.each do |prefix|
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
