# frozen_string_literal: true

require 'mkmf'

# Always use stubs - no option to disable
$CFLAGS << " -DUSE_TCL_STUBS -DUSE_TK_STUBS"

def find_tcltk
  # Try pkg-config first
  tcl_found = pkg_config('tcl') || pkg_config('tcl9.0') || pkg_config('tcl8.6')
  tk_found = pkg_config('tk') || pkg_config('tk9.0') || pkg_config('tk8.6')

  unless tcl_found && tk_found
    # Manual search paths
    tcl_dirs = [
      '/opt/homebrew/opt/tcl-tk',
      '/usr/local/opt/tcl-tk',
      '/usr/local',
      '/usr'
    ]

    tcl_dirs.each do |dir|
      inc = "#{dir}/include"
      lib = "#{dir}/lib"
      # Check for tcl-tk subdirectory (Homebrew layout)
      if File.exist?("#{inc}/tcl-tk/tcl.h")
        inc = "#{inc}/tcl-tk"
      end
      if File.exist?("#{inc}/tcl.h") && File.exist?("#{inc}/tk.h")
        $INCFLAGS << " -I#{inc}"
        $LDFLAGS << " -L#{lib}"
        break
      end
    end
  end

  # Check for required headers
  have_header('tcl.h') or abort "tcl.h not found"
  have_header('tk.h') or abort "tk.h not found"

  # Link against STUB libraries, not main libraries
  # Try versioned stub names first, then unversioned
  tcl_stub = have_library('tclstub9.0') ||
             have_library('tclstub8.6') ||
             have_library('tclstub')

  tk_stub = have_library('tkstub9.0') ||
            have_library('tkstub8.6') ||
            have_library('tkstub')

  # MSYS2/MinGW uses names without dots (tclstub86 instead of tclstub8.6)
  if RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
    tcl_stub ||= have_library('tclstub90') || have_library('tclstub86')
    tk_stub ||= have_library('tkstub90') || have_library('tkstub86')
  end

  # If stub libraries not found by simple name, try via pkg-config
  unless tcl_stub
    # pkg-config may have added them already via --libs
    # Check if we can find the stubs table
    if try_link(<<~CODE)
      #define USE_TCL_STUBS
      #include <tcl.h>
      int main() { return 0; }
    CODE
      tcl_stub = true
    end
  end

  abort "Tcl stub library not found" unless tcl_stub
  abort "Tk stub library not found" unless tk_stub
end

find_tcltk

# Source files for the extension
$srcs = ['tcltkbridge.c', 'tkphoto.c', 'tkfont.c', 'tkutil.c']

create_makefile('tcltklib')
